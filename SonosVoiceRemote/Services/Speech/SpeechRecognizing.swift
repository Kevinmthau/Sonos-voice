import Foundation

enum SpeechPermissionState: Equatable {
    case unknown
    case granted
    case denied
    case restricted

    var statusMessage: String {
        switch self {
        case .unknown:
            return "Microphone and speech permissions have not been requested yet."
        case .granted:
            return "Microphone and speech recognition are available."
        case .denied:
            return "Microphone or speech recognition access was denied."
        case .restricted:
            return "Speech recognition is restricted on this device."
        }
    }
}

enum SpeechRecognizerError: LocalizedError {
    case recognizerUnavailable
    case permissionsDenied
    case audioSessionFailure(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is unavailable right now."
        case .permissionsDenied:
            return "Speech recognition needs microphone and speech permissions."
        case .audioSessionFailure(let details):
            return details
        }
    }
}

protocol SpeechRecognizing: AnyObject {
    func currentPermissionState() async -> SpeechPermissionState
    func requestPermissions() async -> SpeechPermissionState
    func startTranscribing(
        onUpdate: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws
    func stopTranscribing()
}
