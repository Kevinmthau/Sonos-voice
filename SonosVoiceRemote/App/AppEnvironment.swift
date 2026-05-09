import Foundation

enum AppEnvironment {
    @MainActor
    static func makeViewModel() -> VoiceRemoteViewModel {
        VoiceRemoteViewModel(
            speechRecognizer: makeSpeechRecognizer(),
            sonosController: makeSonosController(),
            intentParser: IntentParser()
        )
    }

    static func makeSpeechRecognizer() -> any SpeechRecognizing {
        let configuration = VoiceTranscriptionConfiguration.fromEnvironment()
        return ConfiguredVoiceTranscriber(
            configuration: configuration,
            appleTranscriber: SpeechRecognizerService(),
            openAITranscriber: OpenAITranscriptionService(endpointURL: configuration.openAITranscriptionURL)
        )
    }

    static func makeSonosController() -> any SonosControlling {
        RealSonosController()
    }
}
