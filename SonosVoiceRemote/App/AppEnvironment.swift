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
        SpeechRecognizerService()
    }

    static func makeSonosController() -> any SonosControlling {
        RealSonosController()
    }
}
