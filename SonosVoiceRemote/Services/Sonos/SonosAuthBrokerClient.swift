import AuthenticationServices
import Foundation
import UIKit

@MainActor
protocol SonosAuthBrokerClienting: AnyObject {
    func authorizationURL(state: String) throws -> URL
    func authorize() async throws -> StoredAuthTokens
    func handleAuthorizationCallback(_ url: URL, expectedState: String?) async throws -> StoredAuthTokens
    func refresh(refreshToken: String) async throws -> StoredAuthTokens
    func canHandleAuthorizationCallback(_ url: URL) -> Bool
}

@MainActor
final class SonosAuthBrokerClient: NSObject, SonosAuthBrokerClienting {
    private struct ExchangeRequest: Encodable {
        let code: String
        let state: String?
        let callbackURL: String

        enum CodingKeys: String, CodingKey {
            case code
            case state
            case callbackURL = "callback_url"
        }
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct BrokerTokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private struct BrokerErrorResponse: Decodable {
        let error: String?
        let message: String?

        var detail: String? {
            message ?? error
        }
    }

    private let baseURL: URL?
    private let callbackURL: URL
    private let session: URLSession
    private var authenticationSession: ASWebAuthenticationSession?

    init(baseURL: URL?, callbackURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.callbackURL = callbackURL
        self.session = session
        super.init()
    }

    func authorizationURL(state: String) throws -> URL {
        let url = try brokerURL(path: "sonos/oauth/start")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SonosControllerError.notConfigured("Sonos auth broker start URL could not be built.")
        }

        components.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "callback_url", value: callbackURL.absoluteString)
        ]

        guard let resolvedURL = components.url else {
            throw SonosControllerError.notConfigured("Sonos auth broker start URL could not be built.")
        }

        return resolvedURL
    }

    func authorize() async throws -> StoredAuthTokens {
        let state = UUID().uuidString
        let signInURL = try authorizationURL(state: state)
        guard let callbackScheme = callbackURL.scheme else {
            throw SonosControllerError.notConfigured("Sonos callback URL is invalid.")
        }

        let callback = try await startAuthenticationSession(
            authorizationURL: signInURL,
            callbackURLScheme: callbackScheme
        )
        return try await handleAuthorizationCallback(callback, expectedState: state)
    }

    func handleAuthorizationCallback(_ url: URL, expectedState: String?) async throws -> StoredAuthTokens {
        guard canHandleAuthorizationCallback(url) else {
            throw SonosControllerError.transportFailure("Received an unexpected Sonos authorization callback URL.")
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        if let error = items.first(where: { $0.name == "error" })?.value {
            let detail = items.first(where: { $0.name == "error_description" })?.value ?? error
            throw SonosControllerError.authenticationRequired(detail)
        }

        let returnedState = items.first(where: { $0.name == "state" })?.value
        if let expectedState, returnedState != expectedState {
            throw SonosControllerError.authenticationRequired("Sonos sign-in state did not match. Sign in again to continue.")
        }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw SonosControllerError.authenticationRequired("The Sonos callback did not include an authorization code.")
        }

        return try await exchange(code: code, state: returnedState)
    }

    func refresh(refreshToken: String) async throws -> StoredAuthTokens {
        guard !refreshToken.isEmpty else {
            throw SonosControllerError.authenticationRequired("Sonos refresh token is missing. Sign in again.")
        }

        let response: BrokerTokenResponse = try await send(
            path: "sonos/oauth/refresh",
            body: RefreshRequest(refreshToken: refreshToken)
        )
        return storedTokens(from: response)
    }

    func canHandleAuthorizationCallback(_ url: URL) -> Bool {
        guard let expectedScheme = callbackURL.scheme?.lowercased() else {
            return false
        }

        guard url.scheme?.lowercased() == expectedScheme else {
            return false
        }

        if let expectedHost = callbackURL.host?.lowercased(), !expectedHost.isEmpty {
            guard url.host?.lowercased() == expectedHost else {
                return false
            }
        }

        if !callbackURL.path.isEmpty {
            return url.path == callbackURL.path
        }

        return true
    }

    private func exchange(code: String, state: String?) async throws -> StoredAuthTokens {
        let response: BrokerTokenResponse = try await send(
            path: "sonos/oauth/exchange",
            body: ExchangeRequest(
                code: code,
                state: state,
                callbackURL: callbackURL.absoluteString
            )
        )
        return storedTokens(from: response)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: try brokerURL(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SonosControllerError.transportFailure("Sonos auth broker returned an invalid response.")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let detail = (try? JSONDecoder().decode(BrokerErrorResponse.self, from: data).detail)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw SonosControllerError.authenticationRequired("Sonos auth broker failed: \(detail)")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SonosControllerError.transportFailure("Sonos auth broker response decoding failed: \(error.localizedDescription)")
        }
    }

    private func brokerURL(path: String) throws -> URL {
        guard var url = baseURL else {
            throw SonosControllerError.notConfigured("Set SonosAuthBrokerBaseURL before signing in to Sonos.")
        }

        for segment in path.split(separator: "/") {
            url.appendPathComponent(String(segment))
        }
        return url
    }

    private func storedTokens(from response: BrokerTokenResponse) -> StoredAuthTokens {
        StoredAuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }

    private func startAuthenticationSession(
        authorizationURL: URL,
        callbackURLScheme: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.authenticationSession = nil
                }

                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    continuation.resume(throwing: SonosControllerError.authenticationRequired("Sonos sign-in was canceled."))
                    return
                }

                if let error {
                    continuation.resume(throwing: SonosControllerError.authenticationRequired(error.localizedDescription))
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: SonosControllerError.authenticationRequired("Sonos sign-in did not complete."))
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session

            if !session.start() {
                authenticationSession = nil
                continuation.resume(throwing: SonosControllerError.authenticationRequired("Sonos sign-in could not be started."))
            }
        }
    }
}

extension SonosAuthBrokerClient: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        ?? ASPresentationAnchor()
    }
}
