import Foundation

enum SpeechPermissionState: Equatable {
    case unknown
    case granted
    case denied
    case restricted

    var statusMessage: String {
        switch self {
        case .unknown:
            return "Microphone permission has not been requested yet."
        case .granted:
            return "Microphone access is available."
        case .denied:
            return "Microphone access was denied."
        case .restricted:
            return "Microphone access is restricted on this device."
        }
    }
}

enum SpeechRecognizerError: LocalizedError {
    case recognizerUnavailable
    case permissionsDenied
    case missingOpenAIAPIKey
    case audioSessionFailure(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Voice transcription is unavailable right now."
        case .permissionsDenied:
            return "Voice transcription needs microphone permission."
        case .missingOpenAIAPIKey:
            return "Add an OpenAI API key in Settings before using voice transcription."
        case .audioSessionFailure(let details):
            return details
        }
    }
}

protocol SpeechRecognizing: AnyObject {
    var sourceDescription: String { get }
    var usesDeferredTranscription: Bool { get }

    func currentPermissionState() async -> SpeechPermissionState
    func requestPermissions() async -> SpeechPermissionState
    func startTranscribing(
        onUpdate: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws
    func stopTranscribing() async throws -> String?
    func cancelTranscribing()
}

protocol VoiceCommandContextUpdating: AnyObject {
    func updateCommandContext(roomNames: [String])
}
