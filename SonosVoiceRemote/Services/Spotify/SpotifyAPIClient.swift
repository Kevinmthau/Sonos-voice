import Foundation

protocol SpotifyAPIClienting: Sendable {
    func connectionState() async -> SpotifyConnectionState
    func makeAuthorizationRequest() async throws -> SpotifyAuthorizationRequest
    func exchangeAuthorizationCode(_ code: String, codeVerifier: String) async throws
    func searchTracks(query: String, market: String, limit: Int) async throws -> [SpotifyTrack]
    func availableDevices() async throws -> [SpotifyDevice]
    func transferPlayback(deviceID: String, play: Bool) async throws
    func playTrack(uri: String, deviceID: String) async throws
    func clearTokens() async
}

actor SpotifyAPIClient: SpotifyAPIClienting {
    private let configuration: SpotifyConfiguration
    private let session: URLSession
    private let tokenStore: any SpotifyTokenStoring
    private let decoder = JSONDecoder()

    init(
        configuration: SpotifyConfiguration,
        session: URLSession = .shared,
        tokenStore: any SpotifyTokenStoring = SpotifyTokenStore()
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = tokenStore
    }

    func connectionState() async -> SpotifyConnectionState {
        if let configurationMessage = configuration.configurationMessage {
            return .configurationRequired(configurationMessage)
        }

        let tokens = currentTokens()
        let hasUsableAccessToken = tokens.accessToken?.isEmpty == false
            && (tokens.expiresAt.map { $0 > Date().addingTimeInterval(60) } ?? true)
        let hasRefreshToken = tokens.refreshToken?.isEmpty == false

        if hasUsableAccessToken || hasRefreshToken {
            return .connected("Spotify is connected for music search and playback.")
        }

        return .authenticationRequired()
    }

    func makeAuthorizationRequest() async throws -> SpotifyAuthorizationRequest {
        try SpotifyAuthorizationRequest.make(configuration: configuration)
    }

    func exchangeAuthorizationCode(_ code: String, codeVerifier: String) async throws {
        if let configurationMessage = configuration.configurationMessage {
            throw SpotifyPlaybackError.configurationRequired(configurationMessage)
        }

        guard let clientID = configuration.clientID else {
            throw SpotifyPlaybackError.configurationRequired("Set SpotifyClientID before signing in to Spotify.")
        }

        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded([
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURL.absoluteString),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyPlaybackError.transportFailure("Spotify token exchange returned an invalid response.")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let detail = decodeErrorDetail(from: data) ?? "Spotify sign-in failed."
            throw SpotifyPlaybackError.authenticationRequired(detail)
        }

        let tokenResponse = try decoder.decode(SpotifyOAuthTokenResponse.self, from: data)
        tokenStore.save(
            SpotifyStoredAuthTokens(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
                scope: tokenResponse.scope
            )
        )
    }

    func searchTracks(query: String, market: String = "US", limit: Int = 5) async throws -> [SpotifyTrack] {
        let response: SpotifySearchResponse = try await send(
            path: "search",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "track"),
                URLQueryItem(name: "market", value: market),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        return response.tracks.items
    }

    func availableDevices() async throws -> [SpotifyDevice] {
        let response: SpotifyDevicesResponse = try await send(path: "me/player/devices", method: "GET")
        return response.devices
    }

    func transferPlayback(deviceID: String, play: Bool = false) async throws {
        try await sendNoContent(
            path: "me/player",
            method: "PUT",
            body: SpotifyTransferPlaybackRequest(deviceIds: [deviceID], play: play)
        )
    }

    func playTrack(uri: String, deviceID: String) async throws {
        try await sendNoContent(
            path: "me/player/play",
            method: "PUT",
            queryItems: [URLQueryItem(name: "device_id", value: deviceID)],
            body: SpotifyPlayTrackRequest(uris: [uri])
        )
    }

    func clearTokens() async {
        tokenStore.delete()
    }

    private func sendNoContent<Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Body
    ) async throws {
        let bodyData = try JSONEncoder().encode(body)
        let _: SpotifyEmptyResponse = try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        bodyData: Data? = nil,
        retryOnAuthenticationFailure: Bool = true
    ) async throws -> Response {
        let request = try await makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyPlaybackError.transportFailure("Spotify returned an invalid response.")
        }

        if httpResponse.statusCode == 401 {
            if retryOnAuthenticationFailure, try await refreshAccessTokenIfPossible() {
                return try await send(
                    path: path,
                    method: method,
                    queryItems: queryItems,
                    bodyData: bodyData,
                    retryOnAuthenticationFailure: false
                )
            }

            tokenStore.delete()
            throw SpotifyPlaybackError.authenticationRequired(SpotifyConnectionState.defaultAuthenticationDetail)
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw mapHTTPError(statusCode: httpResponse.statusCode, data: data)
        }

        if data.isEmpty, Response.self == SpotifyEmptyResponse.self {
            return SpotifyEmptyResponse() as! Response
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            if data.isEmpty, Response.self == SpotifyEmptyResponse.self {
                return SpotifyEmptyResponse() as! Response
            }

            throw SpotifyPlaybackError.transportFailure("Spotify response decoding failed: \(error.localizedDescription)")
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?
    ) async throws -> URLRequest {
        let accessToken = try await resolveAccessToken()
        let url = try makeAPIURL(path: path, queryItems: queryItems)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func makeAPIURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var url = configuration.apiBaseURL
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for segment in trimmedPath.split(separator: "/") {
            url.appendPathComponent(String(segment))
        }

        if queryItems.isEmpty {
            return url
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SpotifyPlaybackError.transportFailure("Spotify request URL could not be built.")
        }
        components.queryItems = queryItems

        guard let resolvedURL = components.url else {
            throw SpotifyPlaybackError.transportFailure("Spotify request URL could not be built.")
        }
        return resolvedURL
    }

    private func resolveAccessToken() async throws -> String {
        if let configurationMessage = configuration.configurationMessage {
            throw SpotifyPlaybackError.configurationRequired(configurationMessage)
        }

        let tokens = currentTokens()
        if let accessToken = tokens.accessToken,
           !accessToken.isEmpty,
           tokens.expiresAt.map({ $0 > Date().addingTimeInterval(60) }) ?? true {
            return accessToken
        }

        if try await refreshAccessTokenIfPossible(),
           let refreshedAccessToken = currentTokens().accessToken,
           !refreshedAccessToken.isEmpty {
            return refreshedAccessToken
        }

        throw SpotifyPlaybackError.authenticationRequired(SpotifyConnectionState.defaultAuthenticationDetail)
    }

    private func refreshAccessTokenIfPossible() async throws -> Bool {
        let tokens = currentTokens()
        guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else {
            return false
        }

        guard let clientID = configuration.clientID, !clientID.isEmpty else {
            throw SpotifyPlaybackError.configurationRequired("Set SpotifyClientID before refreshing Spotify tokens.")
        }

        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientID)
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyPlaybackError.transportFailure("Spotify token refresh returned an invalid response.")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let detail = decodeErrorDetail(from: data) ?? SpotifyConnectionState.defaultAuthenticationDetail
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                tokenStore.delete()
            }
            throw SpotifyPlaybackError.authenticationRequired(detail)
        }

        let tokenResponse = try decoder.decode(SpotifyOAuthTokenResponse.self, from: data)
        tokenStore.save(
            SpotifyStoredAuthTokens(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken ?? refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
                scope: tokenResponse.scope ?? tokens.scope
            )
        )
        return true
    }

    private func currentTokens() -> SpotifyStoredAuthTokens {
        tokenStore.load() ?? SpotifyStoredAuthTokens(
            accessToken: nil,
            refreshToken: nil,
            expiresAt: nil,
            scope: nil
        )
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> SpotifyPlaybackError {
        if statusCode == 403, decodeErrorIsPremiumRequired(from: data) {
            return .premiumRequired
        }

        if statusCode == 429 {
            return .rateLimited
        }

        let detail = decodeErrorDetail(from: data)
            ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        return .transportFailure("Spotify request failed: \(detail)")
    }

    private func decodeErrorDetail(from data: Data) -> String? {
        try? decoder.decode(SpotifyAPIErrorResponse.self, from: data).detail
    }

    private func decodeErrorIsPremiumRequired(from data: Data) -> Bool {
        guard let error = try? decoder.decode(SpotifyAPIErrorResponse.self, from: data) else {
            return false
        }
        return error.isPremiumRequired
    }

    private func formURLEncoded(_ items: [URLQueryItem]) -> Data? {
        items
            .compactMap { item -> String? in
                guard let value = item.value else { return nil }
                return "\(percentEncode(item.name))=\(percentEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    private func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct SpotifySearchResponse: Decodable {
    let tracks: SpotifyTrackPage
}

private struct SpotifyTrackPage: Decodable {
    let items: [SpotifyTrack]
}

private struct SpotifyDevicesResponse: Decodable {
    let devices: [SpotifyDevice]
}

private struct SpotifyTransferPlaybackRequest: Encodable {
    let deviceIds: [String]
    let play: Bool

    enum CodingKeys: String, CodingKey {
        case deviceIds = "device_ids"
        case play
    }
}

private struct SpotifyPlayTrackRequest: Encodable {
    let uris: [String]
}

private struct SpotifyEmptyResponse: Decodable { }

private struct SpotifyOAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

private struct SpotifyAPIErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?
    let status: Int?
    let message: String?
    let reason: String?

    var detail: String? {
        reason ?? message ?? errorDescription ?? error
    }

    var isPremiumRequired: Bool {
        let values = [reason, message, errorDescription, error]
            .compactMap { $0?.lowercased() }
        return values.contains(where: { $0.contains("premium") || $0.contains("premium_required") })
    }

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errorDescription = try container.decodeIfPresent(String.self, forKey: .errorDescription)

        if let object = try? container.decode(SpotifyAPIErrorObject.self, forKey: .error) {
            error = nil
            status = object.status
            message = object.message
            reason = object.reason
        } else {
            error = try container.decodeIfPresent(String.self, forKey: .error)
            status = nil
            message = nil
            reason = nil
        }
    }
}

private struct SpotifyAPIErrorObject: Decodable {
    let status: Int?
    let message: String?
    let reason: String?
}
