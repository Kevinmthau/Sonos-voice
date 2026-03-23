import Foundation
import SwiftUI

@MainActor
final class VoiceRemoteViewModel: ObservableObject {
    @Published private(set) var rooms: [SonosRoom] = []
    @Published var selectedRoomID: String = ""
    @Published private(set) var connectionState = SonosConnectionState.unavailable("Checking Sonos controller...")
    @Published var selectedHouseholdID: String = ""
    @Published private(set) var transcript = ""
    @Published private(set) var parsedIntent: ParsedVoiceIntent?
    @Published private(set) var statusText = "Discovering Sonos rooms..."
    @Published private(set) var debugLog: [String] = []
    @Published private(set) var isRecording = false
    @Published private(set) var isExecuting = false
    @Published private(set) var permissionState: SpeechPermissionState = .unknown

    private let speechRecognizer: any SpeechRecognizing
    private let sonosController: any SonosControlling
    private let intentParser: any IntentParsing
    private var hasLoaded = false

    init(
        speechRecognizer: any SpeechRecognizing,
        sonosController: any SonosControlling,
        intentParser: any IntentParsing
    ) {
        self.speechRecognizer = speechRecognizer
        self.sonosController = sonosController
        self.intentParser = intentParser
    }

    var selectedRoom: SonosRoom? {
        rooms.first(where: { $0.id == selectedRoomID }) ?? rooms.first
    }

    var selectedRoomName: String {
        selectedRoom?.name ?? "No room selected"
    }

    var households: [SonosHousehold] {
        connectionState.households.sorted { $0.name < $1.name }
    }

    var selectedHouseholdName: String {
        connectionState.selectedHouseholdName
    }

    var householdSummaryText: String {
        if households.isEmpty {
            return connectionState.detail
        }

        return households.map(\.summary).joined(separator: "\n")
    }

    var authorizationURL: URL? {
        connectionState.authorizationURL
    }

    var roomSummaryText: String {
        if rooms.isEmpty {
            return "No Sonos rooms discovered yet."
        }

        return rooms.map(\.name).joined(separator: ", ")
    }

    var parsedIntentSummary: String {
        parsedIntent?.summary ?? "No parsed command yet."
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        appendLog("App started with the real Sonos controller.")
        permissionState = await speechRecognizer.currentPermissionState()
        await refreshConnection()
        await refreshRooms()
    }

    func refreshConnection() async {
        let state = await sonosController.connectionState()
        applyConnectionState(state)
    }

    func refreshRooms() async {
        let state = await sonosController.connectionState()
        applyConnectionState(state, updateStatus: false)

        guard state.isReady else {
            rooms = []
            selectedRoomID = ""
            statusText = state.detail
            appendLog(state.detail)
            return
        }

        do {
            let discoveredRooms = try await sonosController.discoverRooms()
            rooms = discoveredRooms.sorted { $0.name < $1.name }

            if selectedRoomID.isEmpty || rooms.contains(where: { $0.id == selectedRoomID }) == false {
                selectedRoomID = rooms.first?.id ?? ""
            }

            statusText = rooms.isEmpty
                ? "No Sonos rooms discovered."
                : "Ready. Found \(rooms.count) Sonos room\(rooms.count == 1 ? "" : "s")."
            appendLog(statusText)
        } catch {
            statusText = error.localizedDescription
            appendLog("Room discovery failed: \(error.localizedDescription)")
        }
    }

    func connectSonos() async {
        do {
            let state = try await sonosController.connect()
            applyConnectionState(state)
            statusText = state.detail
            appendLog(state.detail)
            await refreshRooms()
        } catch {
            statusText = error.localizedDescription
            appendLog("Sonos connection failed: \(error.localizedDescription)")
            let state = await sonosController.connectionState()
            applyConnectionState(state, updateStatus: false)
        }
    }

    func disconnectSonos() async {
        let state = await sonosController.disconnect()
        rooms = []
        selectedRoomID = ""
        applyConnectionState(state)
        statusText = state.detail
        appendLog(state.detail)
    }

    func updateSelectedHousehold(id: String) async {
        do {
            let state = try await sonosController.selectHousehold(id: id)
            applyConnectionState(state)
            appendLog("Selected Sonos household: \(state.selectedHouseholdName)")
            await refreshRooms()
        } catch {
            statusText = error.localizedDescription
            appendLog("Household selection failed: \(error.localizedDescription)")
        }
    }

    func handleIncomingURL(_ url: URL) async {
        do {
            let state = try await sonosController.handleAuthorizationCallback(url)
            applyConnectionState(state)
            statusText = "Sonos authorization completed."
            appendLog(statusText)
            await refreshRooms()
        } catch {
            statusText = error.localizedDescription
            appendLog("Sonos authorization failed: \(error.localizedDescription)")
            let state = await sonosController.connectionState()
            applyConnectionState(state, updateStatus: false)
        }
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecordingAndExecute()
        } else {
            await startRecording()
        }
    }

    func executeManual(_ action: SonosAction) async {
        let intent = ParsedVoiceIntent(
            originalTranscript: action.displayName,
            action: action,
            targetRoom: selectedRoom?.name,
            contentQuery: nil,
            volumeValue: nil,
            scope: .singleRoom
        )

        parsedIntent = intent
        transcript = ""
        await execute(intent)
    }

    func processTranscript(_ transcript: String) async {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transcript = cleanedTranscript
        parsedIntent = intentParser.parse(cleanedTranscript, availableRooms: rooms, selectedRoom: selectedRoom)

        guard let parsedIntent else {
            statusText = "I couldn't interpret that command."
            appendLog("Parser could not understand: \(cleanedTranscript)")
            return
        }

        await execute(parsedIntent)
    }

    func updateSelectedRoom(id: String) {
        selectedRoomID = id
        if let selectedRoom {
            appendLog("Selected room: \(selectedRoom.name)")
        }
    }

    private func startRecording() async {
        if permissionState != .granted {
            permissionState = await speechRecognizer.requestPermissions()
        }

        guard permissionState == .granted else {
            statusText = permissionState.statusMessage
            appendLog(statusText)
            return
        }

        transcript = ""
        parsedIntent = nil
        statusText = "Listening..."

        do {
            try await speechRecognizer.startTranscribing(
                onUpdate: { [weak self] partial in
                    Task { @MainActor [weak self] in
                        self?.handleTranscriptUpdate(partial)
                    }
                },
                onError: { [weak self] errorMessage in
                    Task { @MainActor [weak self] in
                        self?.isRecording = false
                        self?.statusText = errorMessage
                        self?.appendLog("Speech error: \(errorMessage)")
                    }
                }
            )
            isRecording = true
            appendLog("Speech recognition started.")
        } catch {
            statusText = error.localizedDescription
            appendLog("Speech recognition failed: \(error.localizedDescription)")
        }
    }

    private func stopRecordingAndExecute() async {
        speechRecognizer.stopTranscribing()
        isRecording = false
        appendLog("Speech recognition stopped.")

        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTranscript.isEmpty else {
            statusText = "No speech captured."
            return
        }

        await processTranscript(finalTranscript)
    }

    private func handleTranscriptUpdate(_ partialTranscript: String) {
        transcript = partialTranscript
        parsedIntent = intentParser.parse(partialTranscript, availableRooms: rooms, selectedRoom: selectedRoom)
    }

    private func execute(_ intent: ParsedVoiceIntent) async {
        isExecuting = true
        statusText = "Executing \(intent.action.displayName)..."
        appendLog("Executing intent: \(intent.summary)")

        do {
            let result = try await perform(intent)
            mergeUpdatedRooms(result.updatedRooms)
            statusText = result.message
            appendLog(result.message)
        } catch {
            statusText = error.localizedDescription
            appendLog("Execution failed: \(error.localizedDescription)")
        }

        isExecuting = false
    }

    private func perform(_ intent: ParsedVoiceIntent) async throws -> SonosCommandResult {
        let resolvedRoom = resolveRoom(named: intent.targetRoom)

        switch intent.action {
        case .play:
            if intent.scope == .allRooms {
                return try await sonosController.playEverywhere(query: intent.contentQuery)
            }
            return try await sonosController.play(room: resolvedRoom, query: intent.contentQuery)

        case .pause:
            if intent.scope == .allRooms {
                return try await sonosController.pauseEverywhere()
            }
            return try await sonosController.pause(room: resolvedRoom)

        case .resume:
            if intent.scope == .allRooms {
                return try await sonosController.playEverywhere(query: nil)
            }
            return try await sonosController.resume(room: resolvedRoom)

        case .skip:
            return try await sonosController.skip(room: resolvedRoom)

        case .volumeUp:
            return try await sonosController.volumeUp(room: resolvedRoom)

        case .volumeDown:
            return try await sonosController.volumeDown(room: resolvedRoom)

        case .setVolume:
            return try await sonosController.setVolume(room: resolvedRoom, value: intent.volumeValue ?? 20)

        case .groupAll:
            return try await sonosController.playEverywhere(query: intent.contentQuery)
        }
    }

    private func resolveRoom(named roomName: String?) -> SonosRoom? {
        guard let roomName else {
            return selectedRoom
        }

        return rooms.first(where: { $0.name.caseInsensitiveCompare(roomName) == .orderedSame }) ?? selectedRoom
    }

    private func mergeUpdatedRooms(_ updatedRooms: [SonosRoom]) {
        guard !updatedRooms.isEmpty else { return }
        rooms = updatedRooms.sorted { $0.name < $1.name }
        if rooms.contains(where: { $0.id == selectedRoomID }) == false {
            selectedRoomID = rooms.first?.id ?? ""
        }
    }

    private func applyConnectionState(_ state: SonosConnectionState, updateStatus: Bool = true) {
        connectionState = state
        selectedHouseholdID = state.selectedHouseholdID ?? state.households.first?.id ?? ""

        if updateStatus {
            statusText = state.detail
        }
    }

    private func appendLog(_ message: String) {
        let line = AppLogger.makeLine(message)
        AppLogger.write(line)
        debugLog.insert(line, at: 0)
        debugLog = Array(debugLog.prefix(8))
    }
}
