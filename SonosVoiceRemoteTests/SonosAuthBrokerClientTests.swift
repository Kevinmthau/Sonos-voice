import Foundation
import XCTest
@testable import SonosVoiceRemote

@MainActor
final class SonosAuthBrokerClientTests: XCTestCase {
    func testAuthorizationURLIncludesStateAndCallbackURL() throws {
        let client = makeClient()

        let url = try client.authorizationURL(state: "state-123")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "broker.test")
        XCTAssertEqual(components.path, "/sonos/oauth/start")
        XCTAssertEqual(query["state"], "state-123")
        XCTAssertEqual(query["callback_url"], "sonosvoiceremote://auth/sonos")
    }

    func testCallbackMatchingRequiresConfiguredPath() {
        let client = makeClient()

        XCTAssertTrue(client.canHandleAuthorizationCallback(URL(string: "sonosvoiceremote://auth/sonos?code=broker-code")!))
        XCTAssertFalse(client.canHandleAuthorizationCallback(URL(string: "sonosvoiceremote://auth/spotify?code=spotify-code")!))
        XCTAssertFalse(client.canHandleAuthorizationCallback(URL(string: "sonosvoiceremote://wrong/sonos?code=broker-code")!))
        XCTAssertFalse(client.canHandleAuthorizationCallback(URL(string: "otherapp://auth/sonos?code=broker-code")!))
    }

    func testCallbackExchangePostsCodeToBroker() async throws {
        let session = makeMockSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://broker.test/sonos/oauth/exchange")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(request.testJSONBody)
            XCTAssertEqual(body["code"] as? String, "broker-code")
            XCTAssertEqual(body["state"] as? String, "state-123")
            XCTAssertEqual(body["callback_url"] as? String, "sonosvoiceremote://auth/sonos")

            return Self.response(
                request: request,
                statusCode: 200,
                body: #"{"access_token":"sonos-access","refresh_token":"sonos-refresh","expires_in":3600}"#
            )
        }
        let client = makeClient(session: session)

        let tokens = try await client.handleAuthorizationCallback(
            URL(string: "sonosvoiceremote://auth/sonos?code=broker-code&state=state-123")!,
            expectedState: "state-123"
        )

        XCTAssertEqual(tokens.accessToken, "sonos-access")
        XCTAssertEqual(tokens.refreshToken, "sonos-refresh")
        XCTAssertGreaterThan(try XCTUnwrap(tokens.expiresAt).timeIntervalSinceNow, 3500)
    }

    func testDeniedCallbackDoesNotCallBroker() async {
        let client = makeClient(session: makeUnexpectedSession())

        do {
            _ = try await client.handleAuthorizationCallback(
                URL(string: "sonosvoiceremote://auth/sonos?error=access_denied&error_description=Nope")!,
                expectedState: "state-123"
            )
            XCTFail("Expected authenticationRequired error.")
        } catch SonosControllerError.authenticationRequired(let message) {
            XCTAssertEqual(message, "Nope")
        } catch {
            XCTFail("Expected authenticationRequired error, got \(error).")
        }
    }

    func testStateMismatchDoesNotCallBroker() async {
        let client = makeClient(session: makeUnexpectedSession())

        do {
            _ = try await client.handleAuthorizationCallback(
                URL(string: "sonosvoiceremote://auth/sonos?code=broker-code&state=wrong-state")!,
                expectedState: "state-123"
            )
            XCTFail("Expected authenticationRequired error.")
        } catch SonosControllerError.authenticationRequired(let message) {
            XCTAssertEqual(message, "Sonos sign-in state did not match. Sign in again to continue.")
        } catch {
            XCTFail("Expected authenticationRequired error, got \(error).")
        }
    }

    func testRefreshFailureSurfacesBrokerMessage() async {
        let session = makeMockSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://broker.test/sonos/oauth/refresh")

            let body = try XCTUnwrap(request.testJSONBody)
            XCTAssertEqual(body["refresh_token"] as? String, "stale-refresh")

            return Self.response(
                request: request,
                statusCode: 401,
                body: #"{"message":"refresh token expired"}"#
            )
        }
        let client = makeClient(session: session)

        do {
            _ = try await client.refresh(refreshToken: "stale-refresh")
            XCTFail("Expected authenticationRequired error.")
        } catch SonosControllerError.authenticationRequired(let message) {
            XCTAssertEqual(message, "Sonos auth broker failed: refresh token expired")
        } catch {
            XCTFail("Expected authenticationRequired error, got \(error).")
        }
    }

    private func makeClient(session: URLSession = .shared) -> SonosAuthBrokerClient {
        SonosAuthBrokerClient(
            baseURL: URL(string: "https://broker.test")!,
            callbackURL: URL(string: "sonosvoiceremote://auth/sonos")!,
            session: session
        )
    }

    private func makeUnexpectedSession() -> URLSession {
        makeMockSession { request in
            XCTFail("Broker should not be called, got \(request).")
            return Self.response(request: request, statusCode: 500, body: "")
        }
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        SonosBrokerMockURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SonosBrokerMockURLProtocol.self]
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

private final class SonosBrokerMockURLProtocol: URLProtocol {
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
    var testJSONBody: [String: Any]? {
        guard let data = testBodyData else {
            return nil
        }

        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private var testBodyData: Data? {
        if let httpBody {
            return httpBody
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
        return data
    }
}
