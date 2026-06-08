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

    func testDeferredTranscriptionExecutesReturnedTranscript() async {
        let speechRecognizer = TestSpeechRecognizer(
            stopResult: "set kitchen to 20",
            usesDeferredTranscription: true
        )
        let viewModel = makeViewModel(speechRecognizer: speechRecognizer)
        await viewModel.loadIfNeeded()

        await viewModel.toggleRecording()
        await viewModel.toggleRecording()

        let kitchen = viewModel.rooms.first(where: { $0.name == "Kitchen" })
        XCTAssertEqual(viewModel.transcript, "set kitchen to 20")
        XCTAssertEqual(viewModel.parsedIntent?.action, .setVolume)
        XCTAssertEqual(kitchen?.volume, 20)
        XCTAssertTrue(viewModel.statusText.contains("Kitchen"))
    }

    func testDeferredTranscriptionFailureDoesNotExecute() async {
        let speechRecognizer = TestSpeechRecognizer(
            stopError: SpeechRecognizerError.audioSessionFailure("Cloud transcription unavailable."),
            usesDeferredTranscription: true
        )
        let viewModel = makeViewModel(speechRecognizer: speechRecognizer)
        await viewModel.loadIfNeeded()

        await viewModel.toggleRecording()
        await viewModel.toggleRecording()

        XCTAssertNil(viewModel.parsedIntent)
        XCTAssertEqual(viewModel.statusText, "Cloud transcription unavailable.")
    }

    func testDeferredTranscriptionBlocksNewRecordingUntilUploadFinishes() async {
        let speechRecognizer = TestSpeechRecognizer(
            stopResult: "set kitchen to 20",
            usesDeferredTranscription: true,
            stopDelay: .milliseconds(100)
        )
        let viewModel = makeViewModel(speechRecognizer: speechRecognizer)
        await viewModel.loadIfNeeded()

        await viewModel.toggleRecording()
        XCTAssertEqual(speechRecognizer.startCount, 1)

        let stopTask = Task {
            await viewModel.toggleRecording()
        }

        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(viewModel.isTranscribing)

        await viewModel.toggleRecording()
        XCTAssertEqual(speechRecognizer.startCount, 1)

        await stopTask.value
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertEqual(speechRecognizer.startCount, 1)
    }

    func testMicrophoneToggleRemainsEnabledToStopActiveRecordingWhileExecuting() async {
        let viewModel = makeViewModel()
        await viewModel.loadIfNeeded()

        await viewModel.toggleRecording()
        XCTAssertTrue(viewModel.isRecording)

        let executeTask = Task {
            await viewModel.executeManual(.pause)
        }

        for _ in 0..<20 where !viewModel.isExecuting {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(viewModel.isExecuting)
        XCTAssertFalse(viewModel.isMicrophoneToggleDisabled)

        await viewModel.toggleRecording()
        XCTAssertFalse(viewModel.isRecording)

        await executeTask.value
    }

    func testStoppingRecordingWhileExecutingCapturesTranscriptWithoutStartingSecondCommand() async {
        let speechRecognizer = TestSpeechRecognizer(stopResult: "set kitchen to 30")
        let sonosController = TestSonosController(pauseDelay: .milliseconds(200))
        let viewModel = makeViewModel(speechRecognizer: speechRecognizer, sonosController: sonosController)
        await viewModel.loadIfNeeded()

        await viewModel.toggleRecording()

        let executeTask = Task {
            await viewModel.executeManual(.pause)
        }

        for _ in 0..<20 where !viewModel.isExecuting {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(viewModel.isExecuting)

        await viewModel.toggleRecording()

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(viewModel.transcript, "set kitchen to 30")
        XCTAssertEqual(viewModel.statusText, "Command captured. Wait for the current Sonos command to finish.")

        let countsWhileExecuting = await sonosController.commandCounts()
        XCTAssertEqual(countsWhileExecuting.pause, 1)
        XCTAssertEqual(countsWhileExecuting.setVolume, 0)

        await executeTask.value

        let finalCounts = await sonosController.commandCounts()
        XCTAssertEqual(finalCounts.pause, 1)
        XCTAssertEqual(finalCounts.setVolume, 0)
    }

    func testContentQueryUsesSpotifyPlaybackForSelectedRoom() async {
        let musicPlaybackService = TestMusicPlaybackService()
        let sonosController = TestSonosController()
        let viewModel = makeViewModel(
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService
        )
        await viewModel.loadIfNeeded()

        await viewModel.processTranscript("play Miles Davis in Kitchen")

        XCTAssertEqual(viewModel.parsedIntent?.action, .play)
        XCTAssertEqual(musicPlaybackService.preparedQueries, ["miles davis"])
        XCTAssertEqual(musicPlaybackService.preparedRoomNames, ["Kitchen"])
        XCTAssertEqual(musicPlaybackService.startedDeviceIDs, ["spotify-kitchen"])

        let counts = await sonosController.commandCounts()
        XCTAssertEqual(counts.play, 0)
        XCTAssertEqual(counts.playEverywhere, 0)

        let kitchen = viewModel.rooms.first(where: { $0.name == "Kitchen" })
        XCTAssertTrue(kitchen?.isPlaying == true)
        XCTAssertEqual(kitchen?.currentContent, "So What - Miles Davis")
        XCTAssertTrue(viewModel.statusText.contains("So What"))
    }

    func testNoSpotifyAuthReturnsSignInStatusAndDoesNotCallSonosPlayback() async {
        let musicPlaybackService = TestMusicPlaybackService(
            state: .authenticationRequired("Sign in to Spotify before searching music.")
        )
        let sonosController = TestSonosController()
        let viewModel = makeViewModel(
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService
        )
        await viewModel.loadIfNeeded()

        await viewModel.processTranscript("play Miles Davis in Kitchen")

        XCTAssertEqual(viewModel.statusText, "Sign in to Spotify before searching music.")
        let counts = await sonosController.commandCounts()
        XCTAssertEqual(counts.play, 0)
        XCTAssertEqual(counts.playEverywhere, 0)
    }

    func testSpotifyPlaybackAuthenticationFailureRefreshesSpotifyConnectionState() async {
        let signedOutState = SpotifyConnectionState.authenticationRequired("Sign in to Spotify before searching music.")
        let musicPlaybackService = TestMusicPlaybackService(
            playbackError: SpotifyPlaybackError.authenticationRequired(signedOutState.detail),
            stateAfterAuthenticationError: signedOutState
        )
        let sonosController = TestSonosController()
        let viewModel = makeViewModel(
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService
        )
        await viewModel.loadIfNeeded()
        XCTAssertEqual(viewModel.spotifyConnectionState.status, .connected)

        await viewModel.processTranscript("play Miles Davis in Kitchen")

        XCTAssertEqual(viewModel.statusText, signedOutState.detail)
        XCTAssertEqual(viewModel.spotifyConnectionState, signedOutState)
        let counts = await sonosController.commandCounts()
        XCTAssertEqual(counts.play, 0)
        XCTAssertEqual(counts.playEverywhere, 0)
    }

    func testNoMatchingSpotifyConnectDeviceReturnsActionableMessage() async {
        let musicPlaybackService = TestMusicPlaybackService(
            playbackError: SpotifyPlaybackError.noMatchingDevice(
                roomName: "Kitchen",
                availableDeviceNames: ["Living Room"]
            )
        )
        let viewModel = makeViewModel(musicPlaybackService: musicPlaybackService)
        await viewModel.loadIfNeeded()

        await viewModel.processTranscript("play Miles Davis in Kitchen")

        XCTAssertTrue(viewModel.statusText.contains("Kitchen is not available as a Spotify Connect device"))
        XCTAssertTrue(viewModel.statusText.contains("Open Spotify"))
    }

    func testSpotifyPremiumRequiredResponseSurfacesPremiumMessage() async {
        let musicPlaybackService = TestMusicPlaybackService(playbackError: SpotifyPlaybackError.premiumRequired)
        let viewModel = makeViewModel(musicPlaybackService: musicPlaybackService)
        await viewModel.loadIfNeeded()

        await viewModel.processTranscript("play Miles Davis in Kitchen")

        XCTAssertEqual(viewModel.statusText, "Spotify Premium is required to start playback on Spotify Connect devices.")
    }

    func testNoSearchResultsDoesNotAlterCurrentSonosPlayback() async {
        let musicPlaybackService = TestMusicPlaybackService(
            playbackError: SpotifyPlaybackError.noSearchResults("miles davis")
        )
        let sonosController = TestSonosController()
        let viewModel = makeViewModel(
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService
        )
        await viewModel.loadIfNeeded()

        await viewModel.processTranscript("play Miles Davis in Kitchen")

        let counts = await sonosController.commandCounts()
        XCTAssertEqual(counts.play, 0)
        XCTAssertEqual(counts.playEverywhere, 0)

        let kitchen = viewModel.rooms.first(where: { $0.name == "Kitchen" })
        XCTAssertFalse(kitchen?.isPlaying == true)
        XCTAssertNil(kitchen?.currentContent)
    }

    func testSpotifyPlaybackEverywhereValidatesSpotifyBeforeGroupingRooms() async {
        let musicPlaybackService = TestMusicPlaybackService(
            state: .authenticationRequired("Sign in to Spotify before searching music.")
        )
        let sonosController = TestSonosController()
        let viewModel = makeViewModel(
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService
        )
        await viewModel.loadIfNeeded()

        await viewModel.processTranscript("play Miles Davis everywhere")

        XCTAssertEqual(viewModel.parsedIntent?.action, .groupAll)
        XCTAssertEqual(viewModel.statusText, "Sign in to Spotify before searching music.")
        XCTAssertEqual(musicPlaybackService.startPlaybackCallCount, 0)

        let counts = await sonosController.commandCounts()
        XCTAssertEqual(counts.playEverywhere, 0)
        XCTAssertEqual(counts.groupEverywhere, 0)

        let sonosRooms = await sonosController.currentRooms()
        XCTAssertFalse(sonosRooms.allSatisfy { $0.groupName == "Everywhere" })
    }

    func testSpotifyPlaybackEverywhereStartFailureReturnsGroupedRooms() async {
        let musicPlaybackService = TestMusicPlaybackService(
            startPlaybackError: SpotifyPlaybackError.premiumRequired
        )
        let sonosController = TestSonosController()
        let viewModel = makeViewModel(
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService
        )
        await viewModel.loadIfNeeded()

        await viewModel.processTranscript("play Miles Davis everywhere")

        XCTAssertEqual(musicPlaybackService.startPlaybackCallCount, 1)
        XCTAssertTrue(viewModel.statusText.contains("Grouped all rooms, but Spotify playback failed"))
        XCTAssertTrue(viewModel.statusText.contains("Spotify Premium is required"))

        let counts = await sonosController.commandCounts()
        XCTAssertEqual(counts.playEverywhere, 0)
        XCTAssertEqual(counts.groupEverywhere, 1)
        XCTAssertTrue(viewModel.rooms.allSatisfy { $0.groupName == "Everywhere" })
    }

    func testSpotifyPlaybackEverywhereStartAuthenticationFailureRefreshesSpotifyConnectionState() async {
        let signedOutState = SpotifyConnectionState.authenticationRequired("Sign in to Spotify before searching music.")
        let musicPlaybackService = TestMusicPlaybackService(
            startPlaybackError: SpotifyPlaybackError.authenticationRequired(signedOutState.detail),
            stateAfterAuthenticationError: signedOutState
        )
        let sonosController = TestSonosController()
        let viewModel = makeViewModel(
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService
        )
        await viewModel.loadIfNeeded()
        XCTAssertEqual(viewModel.spotifyConnectionState.status, .connected)

        await viewModel.processTranscript("play Miles Davis everywhere")

        XCTAssertTrue(viewModel.statusText.contains("Grouped all rooms, but Spotify playback failed"))
        XCTAssertEqual(viewModel.spotifyConnectionState, signedOutState)
        let counts = await sonosController.commandCounts()
        XCTAssertEqual(counts.playEverywhere, 0)
        XCTAssertEqual(counts.groupEverywhere, 1)
    }

    func testSpotifyPlaybackEverywhereStartsPreparedPlaybackAfterGrouping() async {
        let musicPlaybackService = TestMusicPlaybackService()
        let sonosController = TestSonosController(
            playEverywhereError: SonosControllerError.transportFailure("The grouped queue had nothing to resume.")
        )
        let viewModel = makeViewModel(
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService
        )
        await viewModel.loadIfNeeded()
        XCTAssertEqual(viewModel.selectedRoom?.name, "Bedroom")

        await viewModel.processTranscript("play Miles Davis everywhere")

        XCTAssertEqual(viewModel.parsedIntent?.action, .groupAll)
        XCTAssertEqual(musicPlaybackService.preparedQueries, ["miles davis"])
        XCTAssertEqual(musicPlaybackService.preparedRoomNames, ["Bedroom"])
        XCTAssertEqual(musicPlaybackService.startedDeviceIDs, ["spotify-bedroom"])
        XCTAssertEqual(musicPlaybackService.startPlaybackCallCount, 1)

        let counts = await sonosController.commandCounts()
        XCTAssertEqual(counts.playEverywhere, 0)
        XCTAssertEqual(counts.groupEverywhere, 1)

        let sonosRooms = await sonosController.currentRooms()
        XCTAssertEqual(sonosRooms.first(where: \.isCoordinator)?.name, "Kitchen")
        XCTAssertTrue(sonosRooms.allSatisfy { $0.groupName == "Everywhere" })
        XCTAssertTrue(viewModel.rooms.allSatisfy { $0.currentContent == "So What - Miles Davis" })
        XCTAssertTrue(viewModel.statusText.contains("Grouped all rooms. Playing So What"))
    }

    func testVoiceTranscriptionConfigurationDefaultsToDirectOpenAI() {
        let configuration = VoiceTranscriptionConfiguration.directOpenAI

        XCTAssertEqual(configuration.openAITranscriptionURL, VoiceTranscriptionConfiguration.defaultOpenAITranscriptionURL)
        XCTAssertEqual(configuration.openAIModel, VoiceTranscriptionConfiguration.defaultOpenAIModel)
    }

    private func makeViewModel(
        speechRecognizer: any SpeechRecognizing = TestSpeechRecognizer(),
        sonosController: any SonosControlling = TestSonosController(),
        musicPlaybackService: (any MusicPlaybackServicing)? = nil
    ) -> VoiceRemoteViewModel {
        VoiceRemoteViewModel(
            speechRecognizer: speechRecognizer,
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService ?? TestMusicPlaybackService(),
            intentParser: IntentParser()
        )
    }
}

private final class TestSpeechRecognizer: SpeechRecognizing {
    let sourceDescription: String
    let usesDeferredTranscription: Bool
    private(set) var startCount = 0
    private let permissionState: SpeechPermissionState
    private let stopResult: String?
    private let stopError: Error?
    private let stopDelay: Duration?

    init(
        sourceDescription: String = "Test speech",
        permissionState: SpeechPermissionState = .granted,
        stopResult: String? = nil,
        stopError: Error? = nil,
        usesDeferredTranscription: Bool = false,
        stopDelay: Duration? = nil
    ) {
        self.sourceDescription = sourceDescription
        self.permissionState = permissionState
        self.stopResult = stopResult
        self.stopError = stopError
        self.usesDeferredTranscription = usesDeferredTranscription
        self.stopDelay = stopDelay
    }

    func currentPermissionState() async -> SpeechPermissionState {
        permissionState
    }

    func requestPermissions() async -> SpeechPermissionState {
        permissionState
    }

    func startTranscribing(
        onUpdate: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws {
        startCount += 1
    }

    func stopTranscribing() async throws -> String? {
        if let stopError {
            throw stopError
        }

        if let stopDelay {
            try await Task.sleep(for: stopDelay)
        }

        return stopResult
    }

    func cancelTranscribing() { }
}

@MainActor
private final class TestMusicPlaybackService: MusicPlaybackServicing {
    private(set) var preparedQueries: [String] = []
    private(set) var preparedRoomNames: [String] = []
    private(set) var startedDeviceIDs: [String] = []
    private(set) var startPlaybackCallCount = 0
    private var state: SpotifyConnectionState
    private let preparePlaybackError: Error?
    private let startPlaybackError: Error?
    private let stateAfterAuthenticationError: SpotifyConnectionState?

    init(
        state: SpotifyConnectionState = .connected("Spotify is connected for tests."),
        playbackError: Error? = nil,
        preparePlaybackError: Error? = nil,
        startPlaybackError: Error? = nil,
        stateAfterAuthenticationError: SpotifyConnectionState? = nil
    ) {
        self.state = state
        self.preparePlaybackError = preparePlaybackError ?? playbackError
        self.startPlaybackError = startPlaybackError ?? playbackError
        self.stateAfterAuthenticationError = stateAfterAuthenticationError
    }

    func connectionState() async -> SpotifyConnectionState {
        state
    }

    func connect() async throws -> SpotifyConnectionState {
        state = .connected("Spotify is connected for tests.")
        return state
    }

    func disconnect() async -> SpotifyConnectionState {
        state = .authenticationRequired("Sign in to Spotify for tests.")
        return state
    }

    func canHandleAuthorizationCallback(_ url: URL) -> Bool {
        false
    }

    func handleAuthorizationCallback(_ url: URL) async throws -> SpotifyConnectionState {
        state
    }

    func preparePlayback(query: String, room: SonosRoom?) async throws -> PreparedMusicPlayback {
        guard state.isConnected else {
            throw SpotifyPlaybackError.authenticationRequired(state.detail)
        }

        if let preparePlaybackError {
            applyAuthenticationErrorStateIfNeeded(preparePlaybackError)
            throw preparePlaybackError
        }

        let roomName = room?.name ?? "Kitchen"
        preparedQueries.append(query)
        preparedRoomNames.append(roomName)

        return PreparedMusicPlayback(
            query: query,
            roomName: roomName,
            track: SpotifyTrack(
                id: "track-1",
                name: "So What",
                uri: "spotify:track:so-what",
                artists: ["Miles Davis"]
            ),
            device: SpotifyDevice(
                id: "spotify-\(roomName.lowercased().replacingOccurrences(of: " ", with: "-"))",
                name: roomName
            )
        )
    }

    func startPlayback(_ preparedPlayback: PreparedMusicPlayback) async throws -> MusicPlaybackResult {
        startPlaybackCallCount += 1

        if let startPlaybackError {
            applyAuthenticationErrorStateIfNeeded(startPlaybackError)
            throw startPlaybackError
        }

        if let deviceID = preparedPlayback.device.id {
            startedDeviceIDs.append(deviceID)
        }

        return MusicPlaybackResult(
            message: "Playing \(preparedPlayback.track.name) by Miles Davis on \(preparedPlayback.device.name).",
            trackTitle: preparedPlayback.track.name,
            artistName: "Miles Davis",
            deviceName: preparedPlayback.device.name
        )
    }

    func play(query: String, in room: SonosRoom?) async throws -> MusicPlaybackResult {
        let preparedPlayback = try await preparePlayback(query: query, room: room)
        return try await startPlayback(preparedPlayback)
    }

    private func applyAuthenticationErrorStateIfNeeded(_ error: Error) {
        guard let spotifyError = error as? SpotifyPlaybackError,
              case .authenticationRequired = spotifyError,
              let stateAfterAuthenticationError else {
            return
        }

        state = stateAfterAuthenticationError
    }
}

private actor TestSonosController: SonosControlling {
    private var rooms: [SonosRoom]
    private var groups: [SonosGroup]
    private var playCallCount = 0
    private var pauseCallCount = 0
    private var setVolumeCallCount = 0
    private var playEverywhereCallCount = 0
    private var groupEverywhereCallCount = 0
    private let pauseDelay: Duration
    private let playEverywhereError: SonosControllerError?
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
    ], pauseDelay: Duration = .milliseconds(60), playEverywhereError: SonosControllerError? = nil) {
        self.rooms = seedRooms
        self.groups = seedRooms.map { SonosGroup(id: $0.id, name: $0.name, roomNames: [$0.name]) }
        self.pauseDelay = pauseDelay
        self.playEverywhereError = playEverywhereError
    }

    func commandCounts() -> (pause: Int, setVolume: Int, play: Int, playEverywhere: Int, groupEverywhere: Int) {
        (pauseCallCount, setVolumeCallCount, playCallCount, playEverywhereCallCount, groupEverywhereCallCount)
    }

    func currentRooms() -> [SonosRoom] {
        rooms
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
        playCallCount += 1
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
        pauseCallCount += 1
        let target = try resolveRoom(from: room)
        try await Task.sleep(for: pauseDelay)

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
        setVolumeCallCount += 1
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

    func groupEverywhere() async throws -> SonosCommandResult {
        groupEverywhereCallCount += 1
        try await Task.sleep(for: .milliseconds(90))

        let currentRooms = rooms
        groups = [SonosGroup(id: "everywhere", name: "Everywhere", roomNames: currentRooms.map(\.name))]

        rooms = currentRooms.map { room in
            var updated = room
            updated.groupName = "Everywhere"
            updated.isCoordinator = room.name == currentRooms.first?.name
            return updated
        }

        return SonosCommandResult(message: "Test Sonos grouped all rooms.", updatedRooms: rooms)
    }

    func playEverywhere(query: String?) async throws -> SonosCommandResult {
        playEverywhereCallCount += 1
        if let playEverywhereError {
            throw playEverywhereError
        }

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
