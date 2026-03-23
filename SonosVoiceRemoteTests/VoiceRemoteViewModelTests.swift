import XCTest
@testable import SonosVoiceRemote

@MainActor
final class VoiceRemoteViewModelTests: XCTestCase {
    func testLoadDiscoversRoomsAndSelectsFirstAlphabetically() async {
        let viewModel = makeViewModel()

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.rooms.count, 4)
        XCTAssertEqual(viewModel.selectedRoom?.name, "Bedroom")
        XCTAssertTrue(viewModel.statusText.contains("Found 4"))
    }

    func testLoadPublishesReadyConnectionState() async {
        let viewModel = makeViewModel()

        await viewModel.loadIfNeeded()

        XCTAssertTrue(viewModel.connectionState.isReady)
        XCTAssertEqual(viewModel.selectedHouseholdName, "Test Household")
    }

    func testProcessTranscriptExecutesSetVolume() async throws {
        let viewModel = makeViewModel()
        await viewModel.loadIfNeeded()

        await viewModel.processTranscript("set kitchen to 20")

        let kitchen = viewModel.rooms.first(where: { $0.name == "Kitchen" })
        XCTAssertEqual(viewModel.parsedIntent?.action, .setVolume)
        XCTAssertEqual(kitchen?.volume, 20)
        XCTAssertTrue(viewModel.statusText.contains("Kitchen"))
    }

    func testProcessTranscriptPausesEverywhere() async {
        let viewModel = makeViewModel()
        await viewModel.loadIfNeeded()
        await viewModel.processTranscript("play jazz everywhere")

        await viewModel.processTranscript("pause everywhere")

        XCTAssertEqual(viewModel.parsedIntent?.action, .pause)
        XCTAssertEqual(viewModel.parsedIntent?.scope, .allRooms)
        XCTAssertFalse(viewModel.rooms.contains(where: \.isPlaying))
    }

    func testManualVolumeUpUsesSelectedRoom() async {
        let viewModel = makeViewModel()
        await viewModel.loadIfNeeded()
        viewModel.updateSelectedRoom(id: viewModel.rooms.first(where: { $0.name == "Kitchen" })?.id ?? "")

        await viewModel.executeManual(.volumeUp)

        let kitchen = viewModel.rooms.first(where: { $0.name == "Kitchen" })
        XCTAssertEqual(kitchen?.volume, 25)
        XCTAssertTrue(viewModel.statusText.contains("Kitchen"))
    }

    private func makeViewModel() -> VoiceRemoteViewModel {
        VoiceRemoteViewModel(
            speechRecognizer: TestSpeechRecognizer(),
            sonosController: TestSonosController(),
            intentParser: IntentParser()
        )
    }
}

private final class TestSpeechRecognizer: SpeechRecognizing {
    func currentPermissionState() async -> SpeechPermissionState {
        .granted
    }

    func requestPermissions() async -> SpeechPermissionState {
        .granted
    }

    func startTranscribing(
        onUpdate: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws { }

    func stopTranscribing() { }
}

private actor TestSonosController: SonosControlling {
    private var rooms: [SonosRoom]
    private var groups: [SonosGroup]
    private let household = SonosHousehold(
        id: "test-household",
        name: "Test Household",
        roomNames: ["Kitchen", "Living Room", "Bedroom", "Dining Room"]
    )

    init(seedRooms: [SonosRoom] = [
        SonosRoom(name: "Kitchen", volume: 20, isCoordinator: true, groupName: "Kitchen"),
        SonosRoom(name: "Living Room", volume: 25, isCoordinator: true, groupName: "Living Room"),
        SonosRoom(name: "Bedroom", volume: 15, isCoordinator: true, groupName: "Bedroom"),
        SonosRoom(name: "Dining Room", volume: 18, isCoordinator: true, groupName: "Dining Room")
    ]) {
        self.rooms = seedRooms
        self.groups = seedRooms.map { SonosGroup(id: $0.id, name: $0.name, roomNames: [$0.name]) }
    }

    func connectionState() async -> SonosConnectionState {
        .ready(detail: "Connected to the test Sonos controller.", households: [household], selectedHouseholdID: household.id)
    }

    func connect() async throws -> SonosConnectionState {
        .ready(detail: "Connected to the test Sonos controller.", households: [household], selectedHouseholdID: household.id)
    }

    func disconnect() async -> SonosConnectionState {
        .unavailable("Disconnected from the test Sonos controller.")
    }

    func selectHousehold(id: String) async throws -> SonosConnectionState {
        guard id == household.id else {
            throw SonosControllerError.householdNotFound(id)
        }

        return .ready(detail: "Connected to the test Sonos controller.", households: [household], selectedHouseholdID: household.id)
    }

    func authorizationURL() async -> URL? {
        nil
    }

    func handleAuthorizationCallback(_ url: URL) async throws -> SonosConnectionState {
        .ready(detail: "Connected to the test Sonos controller.", households: [household], selectedHouseholdID: household.id)
    }

    func discoverRooms() async throws -> [SonosRoom] {
        try await Task.sleep(for: .milliseconds(120))
        return rooms.sorted { $0.name < $1.name }
    }

    func play(room: SonosRoom?, query: String?) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        try await Task.sleep(for: .milliseconds(80))

        updateRoom(named: target.name) { room in
            room.isPlaying = true
            if let query, !query.isEmpty {
                room.currentContent = query.capitalized
            }
        }

        let message: String
        if let query, !query.isEmpty {
            message = "Test Sonos is playing \(query) in \(target.name)."
        } else {
            message = "Test Sonos resumed playback in \(target.name)."
        }

        return SonosCommandResult(message: message, updatedRooms: rooms)
    }

    func pause(room: SonosRoom?) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        try await Task.sleep(for: .milliseconds(60))

        updateRoom(named: target.name) { room in
            room.isPlaying = false
        }

        return SonosCommandResult(
            message: "Test Sonos paused \(target.name).",
            updatedRooms: rooms
        )
    }

    func resume(room: SonosRoom?) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        try await Task.sleep(for: .milliseconds(60))

        updateRoom(named: target.name) { room in
            room.isPlaying = true
        }

        return SonosCommandResult(
            message: "Test Sonos resumed \(target.name).",
            updatedRooms: rooms
        )
    }

    func skip(room: SonosRoom?) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        try await Task.sleep(for: .milliseconds(60))

        updateRoom(named: target.name) { room in
            room.isPlaying = true
            if let current = room.currentContent, !current.isEmpty {
                room.currentContent = "\(current) (next)"
            } else {
                room.currentContent = "Next Track"
            }
        }

        return SonosCommandResult(
            message: "Test Sonos skipped in \(target.name).",
            updatedRooms: rooms
        )
    }

    func setVolume(room: SonosRoom?, value: Int) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        try await Task.sleep(for: .milliseconds(50))

        let clampedValue = max(0, min(100, value))
        updateRoom(named: target.name) { room in
            room.volume = clampedValue
        }

        return SonosCommandResult(
            message: "Test Sonos set \(target.name) to volume \(clampedValue).",
            updatedRooms: rooms
        )
    }

    func volumeUp(room: SonosRoom?) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        try await Task.sleep(for: .milliseconds(40))

        var finalVolume = target.volume
        updateRoom(named: target.name) { room in
            room.volume = min(100, room.volume + 5)
            finalVolume = room.volume
        }

        return SonosCommandResult(
            message: "Test Sonos raised \(target.name) to \(finalVolume).",
            updatedRooms: rooms
        )
    }

    func volumeDown(room: SonosRoom?) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        try await Task.sleep(for: .milliseconds(40))

        var finalVolume = target.volume
        updateRoom(named: target.name) { room in
            room.volume = max(0, room.volume - 5)
            finalVolume = room.volume
        }

        return SonosCommandResult(
            message: "Test Sonos lowered \(target.name) to \(finalVolume).",
            updatedRooms: rooms
        )
    }

    func playEverywhere(query: String?) async throws -> SonosCommandResult {
        try await Task.sleep(for: .milliseconds(90))

        let currentRooms = rooms
        groups = [SonosGroup(id: "everywhere", name: "Everywhere", roomNames: currentRooms.map(\.name))]
        let content = query?.trimmingCharacters(in: .whitespacesAndNewlines)

        rooms = currentRooms.map { room in
            var updated = room
            updated.isPlaying = true
            updated.groupName = "Everywhere"
            updated.isCoordinator = room.name == currentRooms.first?.name
            if let content, !content.isEmpty {
                updated.currentContent = content.capitalized
            }
            return updated
        }

        let message: String
        if let content, !content.isEmpty {
            message = "Test Sonos grouped all rooms and started \(content)."
        } else {
            message = "Test Sonos grouped all rooms and resumed playback."
        }

        return SonosCommandResult(message: message, updatedRooms: rooms)
    }

    func pauseEverywhere() async throws -> SonosCommandResult {
        try await Task.sleep(for: .milliseconds(70))

        rooms = rooms.map { room in
            var updated = room
            updated.isPlaying = false
            return updated
        }

        return SonosCommandResult(
            message: "Test Sonos paused playback in every room.",
            updatedRooms: rooms
        )
    }

    private func resolveRoom(from room: SonosRoom?) throws -> SonosRoom {
        guard let room else {
            throw SonosControllerError.noRoomSelected
        }

        guard let resolved = rooms.first(where: { $0.id == room.id }) else {
            throw SonosControllerError.roomNotFound(room.name)
        }

        return resolved
    }

    private func updateRoom(named roomName: String, update: (inout SonosRoom) -> Void) {
        guard let index = rooms.firstIndex(where: { $0.name.caseInsensitiveCompare(roomName) == .orderedSame }) else {
            return
        }

        update(&rooms[index])
    }
}
