import Foundation

struct SonosHTTPClient: Sendable {
    let configuration: RealSonosConfiguration
    let session: URLSession
    let tokenStore: SonosTokenStore
    let refreshTokens: (@Sendable (String) async throws -> StoredAuthTokens)?

    func sendNoContent(path: String, method: String) async throws {
        let _: SonosEmptyResponse = try await send(path: path, method: method)
    }

    func sendNoContent<Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws {
        let _: SonosEmptyResponse = try await send(path: path, method: method, body: body)
    }

    func send<Response: Decodable>(
        path: String,
        method: String
    ) async throws -> Response {
        try await send(path: path, method: method, bodyData: nil)
    }

    func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        retryOnAuthenticationFailure: Bool = true
    ) async throws -> Response {
        let bodyData = try JSONEncoder().encode(body)
        return try await send(
            path: path,
            method: method,
            bodyData: bodyData,
            retryOnAuthenticationFailure: retryOnAuthenticationFailure
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        retryOnAuthenticationFailure: Bool = true
    ) async throws -> Response {
        let request = try await makeRequest(path: path, method: method, bodyData: bodyData)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SonosControllerError.transportFailure("The real Sonos API returned an invalid response.")
        }

        if httpResponse.statusCode == 401 {
            if retryOnAuthenticationFailure, try await refreshAccessTokenIfPossible() {
                return try await send(
                    path: path,
                    method: method,
                    bodyData: bodyData,
                    retryOnAuthenticationFailure: false
                )
            }

            throw SonosControllerError.authenticationRequired(configuration.authenticationMessage)
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = (try? JSONDecoder().decode(SonosAPIErrorResponse.self, from: data).detail)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw SonosControllerError.transportFailure("Sonos API request failed: \(message)")
        }

        if data.isEmpty, Response.self == SonosEmptyResponse.self {
            return SonosEmptyResponse() as! Response
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            if data.isEmpty, Response.self == SonosEmptyResponse.self {
                return SonosEmptyResponse() as! Response
            }

            throw SonosControllerError.transportFailure("Sonos API response decoding failed: \(error.localizedDescription)")
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        bodyData: Data?
    ) async throws -> URLRequest {
        let accessToken = try await resolveAccessToken()
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = configuration.controlBaseURL.appendingPathComponent(trimmedPath)

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

    private func resolveAccessToken() async throws -> String {
        let tokens = currentTokens()
        if let accessToken = tokens.accessToken, !accessToken.isEmpty, tokens.expiresAt.map({ $0 > Date().addingTimeInterval(60) }) ?? true {
            return accessToken
        }

        if try await refreshAccessTokenIfPossible(), let refreshedAccessToken = currentTokens().accessToken, !refreshedAccessToken.isEmpty {
            return refreshedAccessToken
        }

        throw SonosControllerError.authenticationRequired(configuration.authenticationMessage)
    }

    private func refreshAccessTokenIfPossible() async throws -> Bool {
        let tokens = currentTokens()
        guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else {
            return false
        }

        guard let refreshTokens else {
            throw SonosControllerError.authenticationRequired("Sonos tokens expired. Sign in again.")
        }

        let refreshedTokens = try await refreshTokens(refreshToken)
        tokenStore.save(refreshedTokens)
        return true
    }

    private func currentTokens() -> StoredAuthTokens {
        tokenStore.load() ?? StoredAuthTokens(accessToken: nil, refreshToken: nil, expiresAt: nil)
    }
}
