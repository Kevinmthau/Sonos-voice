import Foundation
import XCTest
@testable import SonosVoiceRemote

final class OpenAITranscriptionServiceTests: XCTestCase {
    func testMissingAPIKeyDoesNotCallOpenAI() async throws {
        let service = makeService(
            apiKeyStore: TestOpenAIAPIKeyStore(apiKey: nil),
            session: makeUnexpectedSession()
        )
        let recordingURL = try makeRecordingFile(contents: Data("fake-audio".utf8))
        defer { try? FileManager.default.removeItem(at: recordingURL) }

        do {
            _ = try await service.transcribeRecording(at: recordingURL)
            XCTFail("Expected missingOpenAIAPIKey error.")
        } catch SpeechRecognizerError.missingOpenAIAPIKey {
            // Expected.
        } catch {
            XCTFail("Expected missingOpenAIAPIKey error, got \(error).")
        }
    }

    func testSuccessfulTranscriptionBuildsDirectMultipartRequest() async throws {
        let session = makeMockSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.test/v1/audio/transcriptions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 60)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data; boundary=") == true)

            let body = try XCTUnwrap(request.testBodyString)
            XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"model\""))
            XCTAssertTrue(body.contains("gpt-4o-mini-transcribe"))
            XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"response_format\""))
            XCTAssertTrue(body.contains("json"))
            XCTAssertTrue(body.contains("Room names: Kitchen, Living Room."))
            XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\""))
            XCTAssertTrue(body.contains("recording.m4a\""))
            XCTAssertTrue(body.contains("Content-Type: audio/mp4"))
            XCTAssertTrue(body.contains("fake-audio"))

            return Self.response(
                request: request,
                statusCode: 200,
                body: #"{"text":"play Miles Davis in the kitchen"}"#
            )
        }
        let service = makeService(
            apiKeyStore: TestOpenAIAPIKeyStore(apiKey: "test-key"),
            session: session
        )
        service.updateCommandContext(roomNames: ["Kitchen", "Living Room"])
        let recordingURL = try makeRecordingFile(filename: "recording.m4a", contents: Data("fake-audio".utf8))
        defer { try? FileManager.default.removeItem(at: recordingURL) }

        let transcript = try await service.transcribeRecording(at: recordingURL)

        XCTAssertEqual(transcript, "play Miles Davis in the kitchen")
    }

    func testUnauthorizedResponseSurfacesSavedKeyMessage() async throws {
        let service = makeService(
            apiKeyStore: TestOpenAIAPIKeyStore(apiKey: "bad-key"),
            session: makeMockSession { request in
                Self.response(
                    request: request,
                    statusCode: 401,
                    body: #"{"error":{"message":"Invalid API key"}}"#
                )
            }
        )
        let recordingURL = try makeRecordingFile(contents: Data("fake-audio".utf8))
        defer { try? FileManager.default.removeItem(at: recordingURL) }

        do {
            _ = try await service.transcribeRecording(at: recordingURL)
            XCTFail("Expected audioSessionFailure error.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "OpenAI rejected the saved API key. Update it in Settings.")
        }
    }

    func testRateLimitResponseSurfacesRetryMessage() async throws {
        let service = makeService(
            apiKeyStore: TestOpenAIAPIKeyStore(apiKey: "test-key"),
            session: makeMockSession { request in
                Self.response(
                    request: request,
                    statusCode: 429,
                    body: #"{"error":{"message":"Too many requests"}}"#
                )
            }
        )
        let recordingURL = try makeRecordingFile(contents: Data("fake-audio".utf8))
        defer { try? FileManager.default.removeItem(at: recordingURL) }

        do {
            _ = try await service.transcribeRecording(at: recordingURL)
            XCTFail("Expected audioSessionFailure error.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "OpenAI rate limit reached. Try again shortly.")
        }
    }

    func testTimeoutSurfacesTimeoutMessage() async throws {
        let service = makeService(
            apiKeyStore: TestOpenAIAPIKeyStore(apiKey: "test-key"),
            session: makeMockSession { _ in
                throw URLError(.timedOut)
            }
        )
        let recordingURL = try makeRecordingFile(contents: Data("fake-audio".utf8))
        defer { try? FileManager.default.removeItem(at: recordingURL) }

        do {
            _ = try await service.transcribeRecording(at: recordingURL)
            XCTFail("Expected audioSessionFailure error.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "OpenAI transcription timed out. Try again.")
        }
    }

    func testPromptOmitsRoomListWhenNoRoomsAreKnown() {
        let prompt = OpenAITranscriptionRequestBuilder.prompt(roomNames: [])

        XCTAssertTrue(prompt.contains("Expected commands include"))
        XCTAssertFalse(prompt.contains("Room names:"))
    }

    private func makeService(
        apiKeyStore: TestOpenAIAPIKeyStore,
        session: URLSession
    ) -> OpenAITranscriptionService {
        OpenAITranscriptionService(
            configuration: VoiceTranscriptionConfiguration(
                openAITranscriptionURL: URL(string: "https://api.openai.test/v1/audio/transcriptions")!,
                openAIModel: VoiceTranscriptionConfiguration.defaultOpenAIModel
            ),
            apiKeyStore: apiKeyStore,
            session: session
        )
    }

    private func makeRecordingFile(
        filename: String = "recording.m4a",
        contents: Data
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(filename)")
        try contents.write(to: url)
        return url
    }

    private func makeUnexpectedSession() -> URLSession {
        makeMockSession { request in
            XCTFail("OpenAI should not be called, got \(request).")
            return Self.response(request: request, statusCode: 500, body: "")
        }
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        OpenAIMockURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    nonisolated private static func response(
        request: URLRequest,
        statusCode: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data(body.utf8)
        )
    }
}

private final class TestOpenAIAPIKeyStore: OpenAIAPIKeyStoring, @unchecked Sendable {
    private var apiKey: String?

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func loadAPIKey() -> String? {
        apiKey
    }

    func saveAPIKey(_ apiKey: String) {
        self.apiKey = apiKey
    }

    func deleteAPIKey() {
        apiKey = nil
    }
}

private final class OpenAIMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { }
}

private extension URLRequest {
    var testBodyString: String? {
        if let httpBody {
            return String(data: httpBody, encoding: .utf8)
        }

        guard let httpBodyStream else {
            return nil
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while httpBodyStream.hasBytesAvailable {
            let count = httpBodyStream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }

        return String(data: data, encoding: .utf8)
    }
}
