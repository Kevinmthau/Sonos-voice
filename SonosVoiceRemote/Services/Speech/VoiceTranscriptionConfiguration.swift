import Foundation

struct VoiceTranscriptionConfiguration: Equatable {
    let mode: SpeechRecognitionMode
    let openAITranscriptionURL: URL
    let openAITranscriptionToken: String?

    static let defaultOpenAITranscriptionURL = URL(string: "https://sonos-voice.netlify.app/api/transcribe")!

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VoiceTranscriptionConfiguration {
        let rawMode = environment["SONOS_VOICE_TRANSCRIPTION_MODE"]?.lowercased()
        let mode = rawMode.flatMap(SpeechRecognitionMode.init(rawValue:)) ?? .apple
        let url = environment["SONOS_OPENAI_TRANSCRIPTION_URL"]
            .flatMap(URL.init(string:))
            ?? defaultOpenAITranscriptionURL
        let token = environment["SONOS_OPENAI_TRANSCRIPTION_TOKEN"]
            .flatMap { $0.isEmpty ? nil : $0 }

        return VoiceTranscriptionConfiguration(
            mode: mode,
            openAITranscriptionURL: url,
            openAITranscriptionToken: token
        )
    }
}
