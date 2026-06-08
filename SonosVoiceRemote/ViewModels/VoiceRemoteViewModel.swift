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
    @Published private(set) var isTranscribing = false
    @Published private(set) var permissionState: SpeechPermissionState = .unknown
    @Published private(set) var spotifyConnectionState = SpotifyConnectionState.authenticationRequired("Checking Spotify connection...")
    @Published private(set) var hasOpenAIAPIKey = false

    private let speechRecognizer: any SpeechRecognizing
    private let intentParser: any IntentParsing
    private let connectionCoordinator: ConnectionCoordinator
    private let voiceCommandCoordinator: VoiceCommandCoordinator
    private var hasLoaded = false

    init(
        speechRecognizer: any SpeechRecognizing,
        sonosController: any SonosControlling,
        musicPlaybackService: any MusicPlaybackServicing,
        intentParser: any IntentParsing,
        openAIAPIKeyStore: any OpenAIAPIKeyStoring = OpenAIAPIKeyStore()
    ) {
        self.speechRecognizer = speechRecognizer
        self.intentParser = intentParser
        self.connectionCoordinator = ConnectionCoordinator(
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService,
            openAIAPIKeyStore: openAIAPIKeyStore
        )
        self.voiceCommandCoordinator = VoiceCommandCoordinator(
            sonosController: sonosController,
            musicPlaybackService: musicPlaybackService
        )
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

    var spotifyStatusText: String {
        spotifyConnectionState.status.displayName
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

    var transcriptionSummaryText: String {
        let keyStatus = hasOpenAIAPIKey ? "OpenAI key saved." : "OpenAI key missing."
        return "\(speechRecognizer.sourceDescription). \(permissionState.statusMessage) \(keyStatus)"
    }

    var isMicrophoneToggleDisabled: Bool {
        isTranscribing || (isExecuting && !isRecording)
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        appendLog("App started with the real Sonos controller.")
        refreshOpenAIAPIKeyState()
        permissionState = await speechRecognizer.currentPermissionState()
        await refreshConnection()
        await refreshRooms()
        await refreshSpotifyConnection(updateStatus: false)
    }

    func refreshConnection() async {
        let state = await connectionCoordinator.sonosConnectionState()
        applyConnectionState(state)
    }

    func refreshRooms() async {
        let state = await connectionCoordinator.sonosConnectionState()
        applyConnectionState(state, updateStatus: false)

        guard state.isReady else {
            rooms = []
            selectedRoomID = ""
            statusText = state.detail
            appendLog(state.detail)
            return
        }

        do {
            let discoveredRooms = try await connectionCoordinator.discoverRooms()
            rooms = discoveredRooms.sorted { $0.name < $1.name }
            updateSpeechCommandContext()

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

    func saveOpenAIAPIKey(_ apiKey: String) {
        connectionCoordinator.saveOpenAIAPIKey(apiKey)
        refreshOpenAIAPIKeyState()
        statusText = hasOpenAIAPIKey ? "OpenAI API key saved." : "OpenAI API key cleared."
        appendLog(statusText)
    }

    func clearOpenAIAPIKey() {
        connectionCoordinator.clearOpenAIAPIKey()
        refreshOpenAIAPIKeyState()
        statusText = "OpenAI API key cleared."
        appendLog(statusText)
    }

    func refreshSpotifyConnection(updateStatus: Bool = false) async {
        let state = await connectionCoordinator.spotifyConnectionState()
        applySpotifyConnectionState(state, updateStatus: updateStatus)
    }

    func connectSonos() async {
        do {
            let state = try await connectionCoordinator.connectSonos()
            applyConnectionState(state)
            statusText = state.detail
            appendLog(state.detail)
            await refreshRooms()
        } catch {
            statusText = error.localizedDescription
            appendLog("Sonos connection failed: \(error.localizedDescription)")
            let state = await connectionCoordinator.sonosConnectionState()
            applyConnectionState(state, updateStatus: false)
        }
    }

    func disconnectSonos() async {
        let state = await connectionCoordinator.disconnectSonos()
        rooms = []
        selectedRoomID = ""
        applyConnectionState(state)
        statusText = state.detail
        appendLog(state.detail)
    }

    func connectSpotify() async {
        do {
            statusText = "Starting Spotify sign-in..."
            let state = try await connectionCoordinator.connectSpotify()
            applySpotifyConnectionState(state)
            statusText = "Spotify authorization completed."
            appendLog(statusText)
        } catch {
            statusText = error.localizedDescription
            appendLog("Spotify authorization failed: \(error.localizedDescription)")
            await refreshSpotifyConnection(updateStatus: false)
        }
    }

    func disconnectSpotify() async {
        let state = await connectionCoordinator.disconnectSpotify()
        applySpotifyConnectionState(state)
        statusText = state.detail
        appendLog(state.detail)
    }

    func updateSelectedHousehold(id: String) async {
        do {
            let state = try await connectionCoordinator.selectHousehold(id: id)
            applyConnectionState(state)
            appendLog("Selected Sonos household: \(state.selectedHouseholdName)")
            await refreshRooms()
        } catch {
            statusText = error.localizedDescription
            appendLog("Household selection failed: \(error.localizedDescription)")
        }
    }

    func handleIncomingURL(_ url: URL) async {
        if connectionCoordinator.canHandleSpotifyCallback(url) {
            do {
                let state = try await connectionCoordinator.handleSpotifyCallback(url)
                applySpotifyConnectionState(state)
                statusText = "Spotify authorization completed."
                appendLog(statusText)
            } catch {
                statusText = error.localizedDescription
                appendLog("Spotify authorization failed: \(error.localizedDescription)")
                await refreshSpotifyConnection(updateStatus: false)
            }
            return
        }

        do {
            let state = try await connectionCoordinator.handleSonosCallback(url)
            applyConnectionState(state)
            statusText = "Sonos authorization completed."
            appendLog(statusText)
            await refreshRooms()
        } catch {
            statusText = error.localizedDescription
            appendLog("Sonos authorization failed: \(error.localizedDescription)")
            let state = await connectionCoordinator.sonosConnectionState()
            applyConnectionState(state, updateStatus: false)
        }
    }

    func toggleRecording() async {
        guard !isTranscribing else {
            statusText = "Transcription is still in progress."
            return
        }

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
        guard !isTranscribing else {
            statusText = "Transcription is still in progress."
            return
        }

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
        statusText = speechRecognizer.usesDeferredTranscription ? "Recording command..." : "Listening..."
        updateSpeechCommandContext()

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
            appendLog("Speech recognition started with \(speechRecognizer.sourceDescription).")
        } catch {
            statusText = error.localizedDescription
            appendLog("Speech recognition failed: \(error.localizedDescription)")
        }
    }

    private func stopRecordingAndExecute() async {
        let usesDeferredTranscription = speechRecognizer.usesDeferredTranscription
        if usesDeferredTranscription {
            isTranscribing = true
        }

        isRecording = false

        if usesDeferredTranscription {
            statusText = "Transcribing..."
        }

        defer {
            if usesDeferredTranscription {
                isTranscribing = false
            }
        }

        do {
            if let finalTranscript = try await speechRecognizer.stopTranscribing()?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !finalTranscript.isEmpty {
                transcript = finalTranscript
            }
        } catch {
            statusText = error.localizedDescription
            appendLog("Transcription failed: \(error.localizedDescription)")
            return
        }

        appendLog("Speech recognition stopped.")

        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTranscript.isEmpty else {
            statusText = "No speech captured."
            return
        }

        guard !isExecuting else {
            statusText = "Command captured. Wait for the current Sonos command to finish."
            appendLog("Captured voice command while another command was running: \(finalTranscript)")
            return
        }

        await processTranscript(finalTranscript)
    }

    private func handleTranscriptUpdate(_ partialTranscript: String) {
        transcript = partialTranscript
        parsedIntent = intentParser.parse(partialTranscript, availableRooms: rooms, selectedRoom: selectedRoom)
    }

    private func execute(_ intent: ParsedVoiceIntent) async {
        guard !isExecuting else {
            statusText = "Wait for the current Sonos command to finish."
            appendLog("Skipped command while another command was running: \(intent.summary)")
            return
        }

        isExecuting = true
        statusText = "Executing \(intent.action.displayName)..."
        appendLog("Executing intent: \(intent.summary)")

        do {
            let result = try await voiceCommandCoordinator.perform(
                intent,
                rooms: rooms,
                selectedRoom: selectedRoom
            )
            mergeUpdatedRooms(result.updatedRooms)
            if let spotifyState = voiceCommandCoordinator.takePendingSpotifyConnectionState() {
                applySpotifyConnectionState(spotifyState, updateStatus: false)
            }
            statusText = result.message
            appendLog(result.message)
        } catch {
            statusText = error.localizedDescription
            appendLog("Execution failed: \(error.localizedDescription)")
            if let spotifyState = await voiceCommandCoordinator.refreshSpotifyConnectionIfAuthenticationRequired(error) {
                applySpotifyConnectionState(spotifyState, updateStatus: false)
            }
        }

        isExecuting = false
    }

    private func mergeUpdatedRooms(_ updatedRooms: [SonosRoom]) {
        guard !updatedRooms.isEmpty else { return }
        rooms = updatedRooms.sorted { $0.name < $1.name }
        updateSpeechCommandContext()
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

    private func applySpotifyConnectionState(_ state: SpotifyConnectionState, updateStatus: Bool = true) {
        spotifyConnectionState = state

        if updateStatus {
            statusText = state.detail
        }
    }

    private func refreshOpenAIAPIKeyState() {
        hasOpenAIAPIKey = connectionCoordinator.hasOpenAIAPIKey()
    }

    private func updateSpeechCommandContext() {
        (speechRecognizer as? VoiceCommandContextUpdating)?.updateCommandContext(roomNames: rooms.map(\.name))
    }

    private func appendLog(_ message: String) {
        let line = AppLogger.makeLine(message)
        AppLogger.write(line)
        debugLog.insert(line, at: 0)
        debugLog = Array(debugLog.prefix(8))
    }
}
