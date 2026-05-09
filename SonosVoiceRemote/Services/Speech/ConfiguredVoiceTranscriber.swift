import Foundation

final class ConfiguredVoiceTranscriber: SpeechRecognizing {
    private enum ActiveSource {
        case apple
        case openai
    }

    private let configuration: VoiceTranscriptionConfiguration
    private let appleTranscriber: any SpeechRecognizing
    private let openAITranscriber: any SpeechRecognizing
    private var activeSource: ActiveSource?

    var sourceDescription: String {
        activeTranscriber?.sourceDescription ?? configuredSourceDescription
    }

    var usesDeferredTranscription: Bool {
        activeTranscriber?.usesDeferredTranscription ?? (configuration.mode == .openai)
    }

    init(
        configuration: VoiceTranscriptionConfiguration,
        appleTranscriber: any SpeechRecognizing,
        openAITranscriber: any SpeechRecognizing
    ) {
        self.configuration = configuration
        self.appleTranscriber = appleTranscriber
        self.openAITranscriber = openAITranscriber
    }

    func currentPermissionState() async -> SpeechPermissionState {
        switch configuration.mode {
        case .apple:
            return await appleTranscriber.currentPermissionState()
        case .openai:
            return await openAITranscriber.currentPermissionState()
        case .auto:
            let appleState = await appleTranscriber.currentPermissionState()
            if appleState == .granted {
                return .granted
            }

            let openAIState = await openAITranscriber.currentPermissionState()
            if openAIState == .granted {
                return .granted
            }

            return mostActionablePermissionState(appleState, openAIState)
        }
    }

    func requestPermissions() async -> SpeechPermissionState {
        switch configuration.mode {
        case .apple:
            return await appleTranscriber.requestPermissions()
        case .openai:
            return await openAITranscriber.requestPermissions()
        case .auto:
            let appleState = await appleTranscriber.requestPermissions()
            if appleState == .granted {
                return .granted
            }

            let openAIState = await openAITranscriber.requestPermissions()
            if openAIState == .granted {
                return .granted
            }

            return mostActionablePermissionState(appleState, openAIState)
        }
    }

    func startTranscribing(
        onUpdate: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws {
        let selected = await preferredTranscriber()

        do {
            try await selected.transcriber.startTranscribing(onUpdate: onUpdate, onError: onError)
            activeSource = selected.source
        } catch {
            guard configuration.mode == .auto, selected.source == .apple else {
                throw error
            }

            try await openAITranscriber.startTranscribing(onUpdate: onUpdate, onError: onError)
            activeSource = .openai
        }
    }

    func stopTranscribing() async throws -> String? {
        defer {
            activeSource = nil
        }

        return try await activeTranscriber?.stopTranscribing()
    }

    func cancelTranscribing() {
        activeTranscriber?.cancelTranscribing()
        activeSource = nil
    }

    private var activeTranscriber: (any SpeechRecognizing)? {
        guard let activeSource else {
            return nil
        }

        switch activeSource {
        case .apple:
            return appleTranscriber
        case .openai:
            return openAITranscriber
        }
    }

    private var configuredSourceDescription: String {
        switch configuration.mode {
        case .apple:
            return appleTranscriber.sourceDescription
        case .openai:
            return openAITranscriber.sourceDescription
        case .auto:
            return "Automatic speech recognition"
        }
    }

    private func preferredTranscriber() async -> (source: ActiveSource, transcriber: any SpeechRecognizing) {
        switch configuration.mode {
        case .apple:
            return (.apple, appleTranscriber)
        case .openai:
            return (.openai, openAITranscriber)
        case .auto:
            let appleState = await appleTranscriber.currentPermissionState()
            if appleState == .granted {
                return (.apple, appleTranscriber)
            }

            return (.openai, openAITranscriber)
        }
    }

    private func mostActionablePermissionState(
        _ first: SpeechPermissionState,
        _ second: SpeechPermissionState
    ) -> SpeechPermissionState {
        if first == .unknown || second == .unknown {
            return .unknown
        }

        if first == .restricted || second == .restricted {
            return .restricted
        }

        return .denied
    }
}
