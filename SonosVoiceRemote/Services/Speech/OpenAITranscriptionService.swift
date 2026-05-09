import AVFoundation
import Foundation

final class OpenAITranscriptionService: NSObject, SpeechRecognizing {
    private struct TranscriptionResponse: Decodable {
        let text: String?
    }

    private struct ErrorResponse: Decodable {
        let error: String?
        let message: String?

        var detail: String? {
            error ?? message
        }
    }

    private let endpointURL: URL
    private let session: URLSession
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    var sourceDescription: String {
        "OpenAI transcription"
    }

    var usesDeferredTranscription: Bool {
        true
    }

    init(endpointURL: URL, session: URLSession = .shared) {
        self.endpointURL = endpointURL
        self.session = session
        super.init()
    }

    func currentPermissionState() async -> SpeechPermissionState {
        microphonePermissionState()
    }

    func requestPermissions() async -> SpeechPermissionState {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        return granted ? .granted : .denied
    }

    func startTranscribing(
        onUpdate: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws {
        let permissionState = await currentPermissionState()
        guard permissionState == .granted else {
            throw SpeechRecognizerError.permissionsDenied
        }

        cancelTranscribing()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechRecognizerError.audioSessionFailure("Unable to start the audio session.")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sonos-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw SpeechRecognizerError.audioSessionFailure("Unable to start recording from the microphone.")
            }

            audioRecorder = recorder
            recordingURL = url
            onUpdate("")
        } catch {
            cleanupAudioSession()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func stopTranscribing() async throws -> String? {
        guard let url = recordingURL else {
            return nil
        }

        audioRecorder?.stop()
        audioRecorder = nil
        recordingURL = nil
        cleanupAudioSession()

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let transcript = try await uploadRecording(at: url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript.isEmpty ? nil : transcript
    }

    func cancelTranscribing() {
        audioRecorder?.stop()
        audioRecorder = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        cleanupAudioSession()
    }

    private func uploadRecording(at url: URL) async throws -> String {
        let audioData = try Data(contentsOf: url)
        guard !audioData.isEmpty else {
            throw SpeechRecognizerError.audioSessionFailure("No speech audio was captured.")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.httpBody = audioData
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue(url.lastPathComponent, forHTTPHeaderField: "X-Audio-Filename")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechRecognizerError.audioSessionFailure("The transcription service returned an invalid response.")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data).detail)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw SpeechRecognizerError.audioSessionFailure("Transcription failed: \(detail)")
        }

        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        guard let text = decoded.text else {
            throw SpeechRecognizerError.audioSessionFailure("The transcription service did not return any text.")
        }

        return text
    }

    private func microphonePermissionState() -> SpeechPermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    private func cleanupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLogger.write("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
}
