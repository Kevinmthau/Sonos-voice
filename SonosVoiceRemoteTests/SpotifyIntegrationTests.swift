import Foundation
import XCTest
@testable import SonosVoiceRemote

@MainActor
final class SpotifyIntegrationTests: XCTestCase {
    func testAuthorizationURLGenerationIncludesPKCEStateRedirectAndScopes() throws {
        let verifier = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        let state = "state-123"
        let request = try SpotifyAuthorizationRequest.make(
            configuration: makeConfiguration(),
            codeVerifier: verifier,
            state: state
        )

        let components = try XCTUnwrap(URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(request.codeVerifier, verifier)
        XCTAssertEqual(request.state, state)
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "accounts.spotify.test")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["client_id"], "spotify-client")
        XCTAssertEqual(query["redirect_uri"], "sonosvoiceremote://spotify/callback")
        XCTAssertEqual(query["state"], state)
        XCTAssertEqual(query["scope"], "user-read-playback-state user-modify-playback-state")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["code_challenge"], SpotifyPKCE.codeChallenge(for: verifier))
    }

    func testAuthorizationRequestRejectsUnregisteredRedirectScheme() throws {
        let configuration = makeConfiguration(
            redirectURL: URL(string: "customspotify://spotify/callback")!
        )

        XCTAssertThrowsError(
            try SpotifyAuthorizationRequest.make(
                configuration: configuration,
                codeVerifier: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~",
                state: "state-123"
            )
        ) { error in
            guard case SpotifyPlaybackError.configurationRequired(let message) = error else {
                return XCTFail("Expected configurationRequired, got \(error).")
            }

            XCTAssertEqual(
                message,
                "SpotifyRedirectURL must use a registered callback URL scheme: sonosvoiceremote."
            )
        }
    }

    func testAuthorizationRequestAllowsRegisteredRedirectScheme() throws {
        let configuration = makeConfiguration(
            redirectURL: URL(string: "customspotify://spotify/callback")!,
            registeredCallbackURLSchemes: ["customspotify"]
        )

        let request = try SpotifyAuthorizationRequest.make(
            configuration: configuration,
            codeVerifier: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~",
            state: "state-123"
        )
        let components = try XCTUnwrap(URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(query["redirect_uri"], "customspotify://spotify/callback")
    }

    func testAPIClientRefreshesTokenAfterUnauthorizedResponse() async throws {
        let recorder = SpotifyURLProtocolRecorder()
        let store = InMemorySpotifyTokenStore(
            tokens: SpotifyStoredAuthTokens(
                accessToken: "stale-token",
                refreshToken: "refresh-token",
                expiresAt: Date().addingTimeInterval(3600),
                scope: nil
            )
        )
        let session = makeMockSession { request in
            recorder.record(request)

            if request.url?.host == "api.spotify.test" {
                let attempt = recorder.searchCount
                if attempt == 1 {
                    return Self.response(
                        request: request,
                        statusCode: 401,
                        body: #"{"error":{"status":401,"message":"The access token expired"}}"#
                    )
                }

                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-token")
                return Self.response(
                    request: request,
                    statusCode: 200,
                    body: #"{"tracks":{"items":[{"id":"1","name":"So What","uri":"spotify:track:1","artists":[{"name":"Miles Davis"}],"is_playable":true}]}}"#
                )
            }

            XCTAssertEqual(request.url?.host, "accounts.spotify.test")
            let body = request.testBodyString
            XCTAssertTrue(body?.contains("grant_type=refresh_token") == true)
            XCTAssertTrue(body?.contains("refresh_token=refresh-token") == true)
            XCTAssertTrue(body?.contains("client_id=spotify-client") == true)
            return Self.response(
                request: request,
                statusCode: 200,
                body: #"{"access_token":"fresh-token","refresh_token":"new-refresh-token","expires_in":3600,"scope":"user-read-playback-state user-modify-playback-state"}"#
            )
        }

        let client = SpotifyAPIClient(
            configuration: makeConfiguration(),
            session: session,
            tokenStore: store
        )

        let tracks = try await client.searchTracks(query: "Miles Davis", market: "US", limit: 5)

        XCTAssertEqual(tracks.first?.name, "So What")
        XCTAssertEqual(recorder.searchCount, 2)
        XCTAssertEqual(store.load()?.accessToken, "fresh-token")
        XCTAssertEqual(store.load()?.refreshToken, "new-refresh-token")
    }

    func testAPIClientClearsTokensWhenUnauthorizedResponseCannotRefresh() async {
        let store = InMemorySpotifyTokenStore(
            tokens: SpotifyStoredAuthTokens(
                accessToken: "rejected-token",
                refreshToken: nil,
                expiresAt: Date().addingTimeInterval(3600),
                scope: nil
            )
        )
        let session = makeMockSession { request in
            XCTAssertEqual(request.url?.host, "api.spotify.test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer rejected-token")
            return Self.response(
                request: request,
                statusCode: 401,
                body: #"{"error":{"status":401,"message":"The access token expired"}}"#
            )
        }
        let client = SpotifyAPIClient(
            configuration: makeConfiguration(),
            session: session,
            tokenStore: store
        )

        do {
            _ = try await client.searchTracks(query: "Miles Davis", market: "US", limit: 5)
            XCTFail("Expected authenticationRequired error.")
        } catch SpotifyPlaybackError.authenticationRequired(let message) {
            XCTAssertEqual(message, SpotifyConnectionState.defaultAuthenticationDetail)
        } catch {
            XCTFail("Expected authenticationRequired error, got \(error).")
        }

        XCTAssertNil(store.load())
        let state = await client.connectionState()
        XCTAssertEqual(state.status, .authenticationRequired)
    }

    func testAPIClientClearsTokensWhenRetryAfterRefreshIsUnauthorized() async {
        let recorder = SpotifyURLProtocolRecorder()
        let store = InMemorySpotifyTokenStore(
            tokens: SpotifyStoredAuthTokens(
                accessToken: "stale-token",
                refreshToken: "refresh-token",
                expiresAt: Date().addingTimeInterval(3600),
                scope: nil
            )
        )
        let session = makeMockSession { request in
            recorder.record(request)

            if request.url?.host == "api.spotify.test" {
                let attempt = recorder.searchCount
                if attempt == 1 {
                    return Self.response(
                        request: request,
                        statusCode: 401,
                        body: #"{"error":{"status":401,"message":"The access token expired"}}"#
                    )
                }

                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-token")
                return Self.response(
                    request: request,
                    statusCode: 401,
                    body: #"{"error":{"status":401,"message":"Invalid access token"}}"#
                )
            }

            XCTAssertEqual(request.url?.host, "accounts.spotify.test")
            return Self.response(
                request: request,
                statusCode: 200,
                body: #"{"access_token":"fresh-token","refresh_token":"new-refresh-token","expires_in":3600,"scope":"user-read-playback-state user-modify-playback-state"}"#
            )
        }
        let client = SpotifyAPIClient(
            configuration: makeConfiguration(),
            session: session,
            tokenStore: store
        )

        do {
            _ = try await client.searchTracks(query: "Miles Davis", market: "US", limit: 5)
            XCTFail("Expected authenticationRequired error.")
        } catch SpotifyPlaybackError.authenticationRequired(let message) {
            XCTAssertEqual(message, SpotifyConnectionState.defaultAuthenticationDetail)
        } catch {
            XCTFail("Expected authenticationRequired error, got \(error).")
        }

        XCTAssertEqual(recorder.searchCount, 2)
        XCTAssertNil(store.load())
        let state = await client.connectionState()
        XCTAssertEqual(state.status, .authenticationRequired)
    }

    func testAPIClientTreatsExpiredAccessTokenWithoutRefreshTokenAsSignedOut() async {
        let store = InMemorySpotifyTokenStore(
            tokens: SpotifyStoredAuthTokens(
                accessToken: "expired-token",
                refreshToken: nil,
                expiresAt: Date().addingTimeInterval(-60),
                scope: nil
            )
        )
        let client = SpotifyAPIClient(
            configuration: makeConfiguration(),
            session: makeMockSession { request in
                XCTFail("Connection state should not make network requests, got \(request).")
                return Self.response(request: request, statusCode: 500, body: "")
            },
            tokenStore: store
        )

        let state = await client.connectionState()

        XCTAssertEqual(state.status, .authenticationRequired)
    }

    func testDuplicateSpotifyCallbackSharesInFlightExchange() async throws {
        let authorizationRequest = try SpotifyAuthorizationRequest.make(
            configuration: makeConfiguration(),
            codeVerifier: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~",
            state: "state-123"
        )
        let apiClient = MockSpotifyAPIClient(
            tracks: [],
            devices: [],
            connectionState: .authenticationRequired("Spotify sign-in is still completing."),
            connectionStateAfterExchange: .connected("Spotify mock connected."),
            exchangeDelayNanoseconds: 50_000_000
        )
        let service = SpotifyMusicPlaybackService(
            configuration: makeConfiguration(),
            apiClient: apiClient,
            pendingAuthorization: authorizationRequest
        )
        let callbackURL = URL(string: "sonosvoiceremote://spotify/callback?code=auth-code&state=state-123")!

        async let firstState = service.handleAuthorizationCallback(callbackURL)
        async let secondState = service.handleAuthorizationCallback(callbackURL)
        let states = try await [firstState, secondState]

        XCTAssertEqual(states, [
            .connected("Spotify mock connected."),
            .connected("Spotify mock connected.")
        ])
        let calls = await apiClient.recordedCalls
        XCTAssertEqual(
            calls.filter {
                if case .exchange = $0 {
                    return true
                }
                return false
            }.count,
            1
        )
    }

    func testMismatchedSpotifyErrorCallbackDoesNotConsumePendingAuthorization() async throws {
        let authorizationRequest = try SpotifyAuthorizationRequest.make(
            configuration: makeConfiguration(),
            codeVerifier: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~",
            state: "state-123"
        )
        let apiClient = MockSpotifyAPIClient(
            tracks: [],
            devices: [],
            connectionState: .authenticationRequired("Spotify sign-in is still pending."),
            connectionStateAfterExchange: .connected("Spotify mock connected.")
        )
        let service = SpotifyMusicPlaybackService(
            configuration: makeConfiguration(),
            apiClient: apiClient,
            pendingAuthorization: authorizationRequest
        )
        let mismatchedErrorURL = URL(string: "sonosvoiceremote://spotify/callback?error=access_denied&error_description=denied&state=wrong-state")!

        do {
            _ = try await service.handleAuthorizationCallback(mismatchedErrorURL)
            XCTFail("Expected mismatched state error.")
        } catch SpotifyPlaybackError.invalidAuthorizationCallback(let message) {
            XCTAssertEqual(message, "Spotify sign-in state did not match. Sign in again to continue.")
        } catch {
            XCTFail("Expected mismatched state error, got \(error).")
        }

        let callbackURL = URL(string: "sonosvoiceremote://spotify/callback?code=auth-code&state=state-123")!
        let state = try await service.handleAuthorizationCallback(callbackURL)

        XCTAssertEqual(state, .connected("Spotify mock connected."))
        let calls = await apiClient.recordedCalls
        XCTAssertEqual(
            calls.filter {
                if case .exchange = $0 {
                    return true
                }
                return false
            }.count,
            1
        )
    }

    func testMusicPlaybackSearchesTransfersAndStartsTopPlayableTrack() async throws {
        let apiClient = MockSpotifyAPIClient(
            tracks: [
                SpotifyTrack(
                    id: "unplayable",
                    name: "Unavailable",
                    uri: "spotify:track:unplayable",
                    artists: ["Miles Davis"],
                    isPlayable: false
                ),
                SpotifyTrack(
                    id: "track-1",
                    name: "So What",
                    uri: "spotify:track:1",
                    artists: ["Miles Davis"]
                )
            ],
            devices: [
                SpotifyDevice(id: "device-1", name: "Kitchen speaker")
            ]
        )
        let service = SpotifyMusicPlaybackService(
            configuration: makeConfiguration(),
            apiClient: apiClient
        )

        let result = try await service.play(query: "Miles Davis", in: SonosRoom(name: "Kitchen"))

        XCTAssertEqual(result.trackTitle, "So What")
        XCTAssertEqual(result.artistName, "Miles Davis")
        XCTAssertEqual(result.deviceName, "Kitchen speaker")
        let calls = await apiClient.recordedCalls
        XCTAssertEqual(calls, [
            .search(query: "Miles Davis", market: "US", limit: 5),
            .devices,
            .transfer(deviceID: "device-1", play: false),
            .play(uri: "spotify:track:1", deviceID: "device-1")
        ])
    }

    func testMusicPlaybackSkipsUnusableExactDeviceMatch() async throws {
        let apiClient = MockSpotifyAPIClient(
            tracks: [
                SpotifyTrack(
                    id: "track-1",
                    name: "So What",
                    uri: "spotify:track:1",
                    artists: ["Miles Davis"]
                )
            ],
            devices: [
                SpotifyDevice(id: nil, name: "Kitchen", isRestricted: true),
                SpotifyDevice(id: "device-1", name: "Kitchen speaker")
            ]
        )
        let service = SpotifyMusicPlaybackService(
            configuration: makeConfiguration(),
            apiClient: apiClient
        )

        let result = try await service.play(query: "Miles Davis", in: SonosRoom(name: "Kitchen"))

        XCTAssertEqual(result.deviceName, "Kitchen speaker")
        let calls = await apiClient.recordedCalls
        XCTAssertEqual(calls, [
            .search(query: "Miles Davis", market: "US", limit: 5),
            .devices,
            .transfer(deviceID: "device-1", play: false),
            .play(uri: "spotify:track:1", deviceID: "device-1")
        ])
    }

    func testMusicPlaybackNoMatchingDeviceReturnsActionableMessage() async {
        let apiClient = MockSpotifyAPIClient(
            tracks: [
                SpotifyTrack(
                    id: "track-1",
                    name: "So What",
                    uri: "spotify:track:1",
                    artists: ["Miles Davis"]
                )
            ],
            devices: [
                SpotifyDevice(id: "device-2", name: "Living Room")
            ]
        )
        let service = SpotifyMusicPlaybackService(
            configuration: makeConfiguration(),
            apiClient: apiClient
        )

        do {
            _ = try await service.play(query: "Miles Davis", in: SonosRoom(name: "Kitchen"))
            XCTFail("Expected no matching device error.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Kitchen is not available as a Spotify Connect device"))
            XCTAssertTrue(error.localizedDescription.contains("Available devices: Living Room"))
        }
    }

    func testMusicPlaybackSkipsDeviceNamesThatNormalizeToEmpty() async {
        let apiClient = MockSpotifyAPIClient(
            tracks: [
                SpotifyTrack(
                    id: "track-1",
                    name: "So What",
                    uri: "spotify:track:1",
                    artists: ["Miles Davis"]
                )
            ],
            devices: [
                SpotifyDevice(id: "device-1", name: "Speaker")
            ]
        )
        let service = SpotifyMusicPlaybackService(
            configuration: makeConfiguration(),
            apiClient: apiClient
        )

        do {
            _ = try await service.play(query: "Miles Davis", in: SonosRoom(name: "Kitchen"))
            XCTFail("Expected no matching device error.")
        } catch SpotifyPlaybackError.noMatchingDevice(let roomName, let availableDeviceNames) {
            XCTAssertEqual(roomName, "Kitchen")
            XCTAssertEqual(availableDeviceNames, ["Speaker"])
        } catch {
            XCTFail("Expected no matching device error, got \(error).")
        }

        let calls = await apiClient.recordedCalls
        XCTAssertEqual(calls, [
            .search(query: "Miles Davis", market: "US", limit: 5),
            .devices
        ])
    }

    func testMusicPlaybackDoesNotMatchRoomNameInsideAnotherDeviceToken() async {
        let apiClient = MockSpotifyAPIClient(
            tracks: [
                SpotifyTrack(
                    id: "track-1",
                    name: "So What",
                    uri: "spotify:track:1",
                    artists: ["Miles Davis"]
                )
            ],
            devices: [
                SpotifyDevice(id: "device-1", name: "Garden")
            ]
        )
        let service = SpotifyMusicPlaybackService(
            configuration: makeConfiguration(),
            apiClient: apiClient
        )

        do {
            _ = try await service.play(query: "Miles Davis", in: SonosRoom(name: "Den"))
            XCTFail("Expected no matching device error.")
        } catch SpotifyPlaybackError.noMatchingDevice(let roomName, let availableDeviceNames) {
            XCTAssertEqual(roomName, "Den")
            XCTAssertEqual(availableDeviceNames, ["Garden"])
        } catch {
            XCTFail("Expected no matching device error, got \(error).")
        }

        let calls = await apiClient.recordedCalls
        XCTAssertEqual(calls, [
            .search(query: "Miles Davis", market: "US", limit: 5),
            .devices
        ])
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

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        SpotifyMockURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpotifyMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeConfiguration(
        redirectURL: URL = URL(string: "sonosvoiceremote://spotify/callback")!,
        registeredCallbackURLSchemes: Set<String> = [SpotifyConfiguration.defaultCallbackURLScheme]
    ) -> SpotifyConfiguration {
        SpotifyConfiguration(
            apiBaseURL: URL(string: "https://api.spotify.test/v1")!,
            authorizationURL: URL(string: "https://accounts.spotify.test/authorize")!,
            tokenURL: URL(string: "https://accounts.spotify.test/api/token")!,
            redirectURL: redirectURL,
            clientID: "spotify-client",
            scopes: SpotifyConfiguration.requiredScopes,
            market: "US",
            registeredCallbackURLSchemes: registeredCallbackURLSchemes
        )
    }
}

private enum SpotifyCall: Equatable {
    case exchange(code: String, codeVerifier: String)
    case search(query: String, market: String, limit: Int)
    case devices
    case transfer(deviceID: String, play: Bool)
    case play(uri: String, deviceID: String)
}

private actor MockSpotifyAPIClient: SpotifyAPIClienting {
    private let tracks: [SpotifyTrack]
    private let devices: [SpotifyDevice]
    private let authorizationRequest: SpotifyAuthorizationRequest?
    private let initialConnectionState: SpotifyConnectionState
    private let connectionStateAfterExchange: SpotifyConnectionState?
    private let exchangeDelayNanoseconds: UInt64
    private var calls: [SpotifyCall] = []
    private var didExchangeAuthorizationCode = false

    init(
        tracks: [SpotifyTrack],
        devices: [SpotifyDevice],
        authorizationRequest: SpotifyAuthorizationRequest? = nil,
        connectionState: SpotifyConnectionState = .connected("Spotify mock connected."),
        connectionStateAfterExchange: SpotifyConnectionState? = nil,
        exchangeDelayNanoseconds: UInt64 = 0
    ) {
        self.tracks = tracks
        self.devices = devices
        self.authorizationRequest = authorizationRequest
        self.initialConnectionState = connectionState
        self.connectionStateAfterExchange = connectionStateAfterExchange
        self.exchangeDelayNanoseconds = exchangeDelayNanoseconds
    }

    var recordedCalls: [SpotifyCall] {
        calls
    }

    func connectionState() async -> SpotifyConnectionState {
        if didExchangeAuthorizationCode, let connectionStateAfterExchange {
            return connectionStateAfterExchange
        }
        return initialConnectionState
    }

    func makeAuthorizationRequest() async throws -> SpotifyAuthorizationRequest {
        guard let authorizationRequest else {
            throw SpotifyPlaybackError.configurationRequired("Mock authorization is not implemented.")
        }
        return authorizationRequest
    }

    func exchangeAuthorizationCode(_ code: String, codeVerifier: String) async throws {
        calls.append(.exchange(code: code, codeVerifier: codeVerifier))
        if exchangeDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: exchangeDelayNanoseconds)
        }
        didExchangeAuthorizationCode = true
    }

    func searchTracks(query: String, market: String, limit: Int) async throws -> [SpotifyTrack] {
        calls.append(.search(query: query, market: market, limit: limit))
        return tracks
    }

    func availableDevices() async throws -> [SpotifyDevice] {
        calls.append(.devices)
        return devices
    }

    func transferPlayback(deviceID: String, play: Bool) async throws {
        calls.append(.transfer(deviceID: deviceID, play: play))
    }

    func playTrack(uri: String, deviceID: String) async throws {
        calls.append(.play(uri: uri, deviceID: deviceID))
    }

    func clearTokens() async { }
}

private final class InMemorySpotifyTokenStore: SpotifyTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: SpotifyStoredAuthTokens?

    init(tokens: SpotifyStoredAuthTokens?) {
        self.tokens = tokens
    }

    func load() -> SpotifyStoredAuthTokens? {
        lock.lock()
        defer { lock.unlock() }
        return tokens
    }

    func save(_ tokens: SpotifyStoredAuthTokens) {
        lock.lock()
        defer { lock.unlock() }
        self.tokens = tokens
    }

    func delete() {
        lock.lock()
        defer { lock.unlock() }
        tokens = nil
    }
}

private final class SpotifyURLProtocolRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    var searchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.filter { $0.url?.host == "api.spotify.test" }.count
    }

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
    }
}

private final class SpotifyMockURLProtocol: URLProtocol {
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
