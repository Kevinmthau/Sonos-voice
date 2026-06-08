import AVFoundation
import Foundation

final class OpenAITranscriptionService: NSObject, SpeechRecognizing, VoiceCommandContextUpdating {
    private struct TranscriptionResponse: Decodable {
        let text: String?
    }

    private struct ErrorResponse: Decodable {
        private struct ErrorDetail: Decodable {
            let message: String?

            init(message: String?) {
                self.message = message
            }
        }

        private let error: ErrorDetail?
        let message: String?

        var detail: String? {
            error?.message ?? message
        }

        enum CodingKeys: String, CodingKey {
            case error
            case message
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let stringError = try? container.decode(String.self, forKey: .error) {
                error = ErrorDetail(message: stringError)
            } else {
                error = try? container.decode(ErrorDetail.self, forKey: .error)
            }
            message = try? container.decode(String.self, forKey: .message)
        }
    }

    private let requestBuilder: OpenAITranscriptionRequestBuilder
    private let apiKeyStore: any OpenAIAPIKeyStoring
    private let session: URLSession
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var roomNames: [String] = []

    var sourceDescription: String {
        "OpenAI transcription"
    }

    var usesDeferredTranscription: Bool {
        true
    }

    init(
        configuration: VoiceTranscriptionConfiguration,
        apiKeyStore: any OpenAIAPIKeyStoring = OpenAIAPIKeyStore(),
        session: URLSession = .shared
    ) {
        self.requestBuilder = OpenAITranscriptionRequestBuilder(
            endpointURL: configuration.openAITranscriptionURL,
            model: configuration.openAIModel
        )
        self.apiKeyStore = apiKeyStore
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

    func transcribeRecording(at url: URL) async throws -> String {
        try await uploadRecording(at: url)
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

    func updateCommandContext(roomNames: [String]) {
        self.roomNames = roomNames
    }

    private func uploadRecording(at url: URL) async throws -> String {
        guard let apiKey = apiKeyStore.loadAPIKey() else {
            throw SpeechRecognizerError.missingOpenAIAPIKey
        }

        let audioData = try Data(contentsOf: url)
        guard !audioData.isEmpty else {
            throw SpeechRecognizerError.audioSessionFailure("No speech audio was captured.")
        }

        let request = requestBuilder.makeRequest(
            audioData: audioData,
            filename: url.lastPathComponent,
            apiKey: apiKey,
            roomNames: roomNames
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw SpeechRecognizerError.audioSessionFailure("OpenAI transcription timed out. Try again.")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechRecognizerError.audioSessionFailure("The transcription service returned an invalid response.")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data).detail)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            switch httpResponse.statusCode {
            case 401:
                throw SpeechRecognizerError.audioSessionFailure("OpenAI rejected the saved API key. Update it in Settings.")
            case 429:
                throw SpeechRecognizerError.audioSessionFailure("OpenAI rate limit reached. Try again shortly.")
            default:
                throw SpeechRecognizerError.audioSessionFailure("OpenAI transcription failed: \(detail)")
            }
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

struct OpenAITranscriptionRequestBuilder {
    let endpointURL: URL
    let model: String

    func makeRequest(
        audioData: Data,
        filename: String,
        apiKey: String,
        roomNames: [String],
        boundary: String = "Boundary-\(UUID().uuidString)"
    ) -> URLRequest {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            audioData: audioData,
            filename: filename,
            boundary: boundary,
            roomNames: roomNames
        )
        return request
    }

    private func multipartBody(
        audioData: Data,
        filename: String,
        boundary: String,
        roomNames: [String]
    ) -> Data {
        var body = Data()
        body.appendFormField(name: "model", value: model, boundary: boundary)
        body.appendFormField(name: "response_format", value: "json", boundary: boundary)
        body.appendFormField(name: "prompt", value: Self.prompt(roomNames: roomNames), boundary: boundary)
        body.appendFileField(
            name: "file",
            filename: filename,
            contentType: "audio/mp4",
            data: audioData,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")
        return body
    }

    static func prompt(roomNames: [String]) -> String {
        var fragments = [
            "Transcribe a short voice command for a Sonos and Spotify remote.",
            "Expected commands include play, pause, resume, skip, volume up, volume down, set volume, and play everywhere.",
            "Return only the spoken command text."
        ]

        if !roomNames.isEmpty {
            fragments.append("Room names: \(roomNames.joined(separator: ", ")).")
        }

        return fragments.joined(separator: " ")
    }
}

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendFileField(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }

    mutating func appendString(_ value: String) {
        if let data = value.data(using: .utf8) {
            append(data)
        }
    }
}
