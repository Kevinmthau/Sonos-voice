import Foundation

struct VoiceTranscriptionConfiguration: Equatable {
    let openAITranscriptionURL: URL
    let openAIModel: String

    static let defaultOpenAITranscriptionURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    static let defaultOpenAIModel = "gpt-4o-mini-transcribe"

    static let directOpenAI = VoiceTranscriptionConfiguration(
        openAITranscriptionURL: defaultOpenAITranscriptionURL,
        openAIModel: defaultOpenAIModel
    )
}
