import Foundation

enum AppEnvironment {
    @MainActor
    static func makeViewModel() -> VoiceRemoteViewModel {
        let appConfiguration = AppConfiguration.fromBundle()
        let openAIAPIKeyStore = OpenAIAPIKeyStore()

        return VoiceRemoteViewModel(
            speechRecognizer: makeSpeechRecognizer(openAIAPIKeyStore: openAIAPIKeyStore),
            sonosController: makeSonosController(appConfiguration: appConfiguration),
            musicPlaybackService: makeMusicPlaybackService(appConfiguration: appConfiguration),
            intentParser: IntentParser(),
            openAIAPIKeyStore: openAIAPIKeyStore
        )
    }

    static func makeSpeechRecognizer(openAIAPIKeyStore: any OpenAIAPIKeyStoring) -> any SpeechRecognizing {
        OpenAITranscriptionService(
            configuration: .directOpenAI,
            apiKeyStore: openAIAPIKeyStore
        )
    }

    @MainActor
    static func makeSonosController(appConfiguration: AppConfiguration) -> any SonosControlling {
        RealSonosController(configuration: .fromAppConfiguration(appConfiguration))
    }

    @MainActor
    static func makeMusicPlaybackService(appConfiguration: AppConfiguration) -> any MusicPlaybackServicing {
        SpotifyMusicPlaybackService(
            configuration: .fromAppConfiguration(appConfiguration)
        )
    }
}
