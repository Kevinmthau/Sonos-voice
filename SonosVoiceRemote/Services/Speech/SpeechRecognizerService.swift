import AVFoundation
import Foundation
import Speech

final class SpeechRecognizerService: NSObject, SpeechRecognizing {
    private let audioEngine = AVAudioEngine()
    private let locale: Locale
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init(locale: Locale = Locale(identifier: "en_US")) {
        self.locale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    func currentPermissionState() async -> SpeechPermissionState {
        permissionState(for: SFSpeechRecognizer.authorizationStatus())
    }

    func requestPermissions() async -> SpeechPermissionState {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        _ = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        return permissionState(for: speechStatus)
    }

    func startTranscribing(
        onUpdate: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws {
        let permissionState = await currentPermissionState()
        guard permissionState == .granted else {
            throw SpeechRecognizerError.permissionsDenied
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognizerError.recognizerUnavailable
        }

        stopTranscribing()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechRecognizerError.audioSessionFailure("Unable to start the audio session.")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopTranscribing()
            throw SpeechRecognizerError.audioSessionFailure("Unable to start recording from the microphone.")
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                onUpdate(result.bestTranscription.formattedString)
            }

            if let error {
                self?.stopTranscribing()
                onError(error.localizedDescription)
            }
        }
    }

    func stopTranscribing() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLogger.write("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    private func permissionState(for speechStatus: SFSpeechRecognizerAuthorizationStatus) -> SpeechPermissionState {
        let microphoneStatus = AVAudioApplication.shared.recordPermission

        if speechStatus == .restricted {
            return .restricted
        }

        if speechStatus == .denied || microphoneStatus == .denied {
            return .denied
        }

        if speechStatus == .authorized && microphoneStatus == .granted {
            return .granted
        }

        return .unknown
    }
}
