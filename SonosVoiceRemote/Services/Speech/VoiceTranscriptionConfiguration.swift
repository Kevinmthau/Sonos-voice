import Foundation

struct VoiceTranscriptionConfiguration: Equatable {
    let mode: SpeechRecognitionMode
    let openAITranscriptionURL: URL

    static let defaultOpenAITranscriptionURL = URL(string: "https://sonos-voice.netlify.app/api/transcribe")!

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VoiceTranscriptionConfiguration {
        let rawMode = environment["SONOS_VOICE_TRANSCRIPTION_MODE"]?.lowercased()
        let mode = rawMode.flatMap(SpeechRecognitionMode.init(rawValue:)) ?? .apple
        let url = environment["SONOS_OPENAI_TRANSCRIPTION_URL"]
            .flatMap(URL.init(string:))
            ?? defaultOpenAITranscriptionURL

        return VoiceTranscriptionConfiguration(mode: mode, openAITranscriptionURL: url)
    }
}
