import AuthenticationServices
import Foundation
import UIKit

@MainActor
protocol MusicPlaybackServicing: AnyObject {
    func connectionState() async -> SpotifyConnectionState
    func connect() async throws -> SpotifyConnectionState
    func disconnect() async -> SpotifyConnectionState
    func canHandleAuthorizationCallback(_ url: URL) -> Bool
    func handleAuthorizationCallback(_ url: URL) async throws -> SpotifyConnectionState
    func preparePlayback(query: String, room: SonosRoom?) async throws -> PreparedMusicPlayback
    func startPlayback(_ preparedPlayback: PreparedMusicPlayback) async throws -> MusicPlaybackResult
    func play(query: String, in room: SonosRoom?) async throws -> MusicPlaybackResult
}

@MainActor
final class SpotifyMusicPlaybackService: NSObject, MusicPlaybackServicing {
    private let configuration: SpotifyConfiguration
    private let apiClient: any SpotifyAPIClienting
    private var authenticationSession: ASWebAuthenticationSession?
    private var pendingAuthorization: SpotifyAuthorizationRequest?
    private var authorizationExchangeTask: Task<SpotifyConnectionState, Error>?
    private var authorizationExchangeState: String?

    init(
        configuration: SpotifyConfiguration,
        apiClient: (any SpotifyAPIClienting)? = nil,
        pendingAuthorization: SpotifyAuthorizationRequest? = nil
    ) {
        self.configuration = configuration
        self.apiClient = apiClient ?? SpotifyAPIClient(configuration: configuration)
        self.pendingAuthorization = pendingAuthorization
        super.init()
    }

    func connectionState() async -> SpotifyConnectionState {
        await apiClient.connectionState()
    }

    func connect() async throws -> SpotifyConnectionState {
        if let configurationMessage = configuration.configurationMessage {
            throw SpotifyPlaybackError.configurationRequired(configurationMessage)
        }

        let authorizationRequest = try await apiClient.makeAuthorizationRequest()
        guard let callbackURLScheme = configuration.callbackURLScheme else {
            throw SpotifyPlaybackError.configurationRequired("SpotifyRedirectURL is invalid.")
        }

        pendingAuthorization = authorizationRequest
        authorizationExchangeTask = nil
        authorizationExchangeState = nil

        do {
            let callbackURL = try await startAuthenticationSession(
                authorizationURL: authorizationRequest.authorizationURL,
                callbackURLScheme: callbackURLScheme
            )
            return try await handleAuthorizationCallback(callbackURL)
        } catch {
            pendingAuthorization = nil
            throw error
        }
    }

    func disconnect() async -> SpotifyConnectionState {
        await apiClient.clearTokens()
        pendingAuthorization = nil
        authorizationExchangeTask?.cancel()
        authorizationExchangeTask = nil
        authorizationExchangeState = nil
        authenticationSession?.cancel()
        authenticationSession = nil
        return await connectionState()
    }

    func canHandleAuthorizationCallback(_ url: URL) -> Bool {
        configuration.matchesRedirectURL(url)
    }

    func handleAuthorizationCallback(_ url: URL) async throws -> SpotifyConnectionState {
        guard configuration.matchesRedirectURL(url) else {
            throw SpotifyPlaybackError.invalidAuthorizationCallback("Received an unexpected Spotify authorization callback.")
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        if let authorizationExchangeTask {
            let returnedState = items.first(where: { $0.name == "state" })?.value
            guard returnedState == authorizationExchangeState else {
                throw SpotifyPlaybackError.invalidAuthorizationCallback("Spotify sign-in state did not match. Sign in again to continue.")
            }
            return try await authorizationExchangeTask.value
        }

        guard let pendingAuthorization else {
            let state = await connectionState()
            if state.isConnected {
                return state
            }
            throw SpotifyPlaybackError.authenticationRequired("Spotify sign-in expired. Sign in again to continue.")
        }

        let returnedState = items.first(where: { $0.name == "state" })?.value
        guard returnedState == pendingAuthorization.state else {
            throw SpotifyPlaybackError.invalidAuthorizationCallback("Spotify sign-in state did not match. Sign in again to continue.")
        }

        if let error = items.first(where: { $0.name == "error" })?.value {
            self.pendingAuthorization = nil
            let detail = items.first(where: { $0.name == "error_description" })?.value ?? error
            throw SpotifyPlaybackError.authorizationDenied("Spotify sign-in was denied or expired. \(detail)")
        }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            self.pendingAuthorization = nil
            throw SpotifyPlaybackError.authenticationRequired("Spotify did not return an authorization code. Sign in again to continue.")
        }

        self.pendingAuthorization = nil
        authorizationExchangeState = pendingAuthorization.state
        let codeVerifier = pendingAuthorization.codeVerifier
        let exchangeTask = Task { [apiClient] in
            try await apiClient.exchangeAuthorizationCode(code, codeVerifier: codeVerifier)
            return await apiClient.connectionState()
        }
        authorizationExchangeTask = exchangeTask

        do {
            let state = try await exchangeTask.value
            authorizationExchangeTask = nil
            authorizationExchangeState = nil
            return state
        } catch {
            authorizationExchangeTask = nil
            authorizationExchangeState = nil
            throw error
        }
    }

    func preparePlayback(query: String, room: SonosRoom?) async throws -> PreparedMusicPlayback {
        guard let room else {
            throw SpotifyPlaybackError.noRoomSelected
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tracks = try await apiClient.searchTracks(
            query: trimmedQuery,
            market: configuration.market,
            limit: 5
        )

        guard let track = tracks.first(where: { $0.isPlayable != false && !$0.uri.isEmpty }) else {
            throw SpotifyPlaybackError.noSearchResults(trimmedQuery)
        }

        let devices = try await apiClient.availableDevices()
        let device = try matchDevice(forRoomName: room.name, devices: devices)

        return PreparedMusicPlayback(
            query: trimmedQuery,
            roomName: room.name,
            track: track,
            device: device
        )
    }

    func startPlayback(_ preparedPlayback: PreparedMusicPlayback) async throws -> MusicPlaybackResult {
        guard let deviceID = preparedPlayback.device.id, !deviceID.isEmpty else {
            throw SpotifyPlaybackError.restrictedDevice(preparedPlayback.device.name)
        }

        try await apiClient.transferPlayback(deviceID: deviceID, play: false)
        try await apiClient.playTrack(uri: preparedPlayback.track.uri, deviceID: deviceID)

        let artistName = preparedPlayback.track.artists.joined(separator: ", ")
        let displayArtist = artistName.isEmpty ? "Unknown Artist" : artistName

        return MusicPlaybackResult(
            message: "Playing \(preparedPlayback.track.name) by \(displayArtist) on \(preparedPlayback.device.name).",
            trackTitle: preparedPlayback.track.name,
            artistName: displayArtist,
            deviceName: preparedPlayback.device.name
        )
    }

    func play(query: String, in room: SonosRoom?) async throws -> MusicPlaybackResult {
        let preparedPlayback = try await preparePlayback(query: query, room: room)
        return try await startPlayback(preparedPlayback)
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
                    continuation.resume(
                        throwing: SpotifyPlaybackError.authorizationDenied("Spotify sign-in was canceled.")
                    )
                    return
                }

                if let error {
                    continuation.resume(
                        throwing: SpotifyPlaybackError.authorizationDenied(error.localizedDescription)
                    )
                    return
                }

                guard let callbackURL else {
                    continuation.resume(
                        throwing: SpotifyPlaybackError.authenticationRequired("Spotify sign-in did not complete. Sign in again to continue.")
                    )
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session

            guard session.start() else {
                authenticationSession = nil
                continuation.resume(
                    throwing: SpotifyPlaybackError.authorizationDenied("Spotify sign-in could not be started.")
                )
                return
            }
        }
    }

    private func matchDevice(forRoomName roomName: String, devices: [SpotifyDevice]) throws -> SpotifyDevice {
        let normalizedRoomName = Self.normalizeDeviceName(roomName)
        guard !normalizedRoomName.isEmpty else {
            throw SpotifyPlaybackError.noMatchingDevice(
                roomName: roomName,
                availableDeviceNames: devices.map(\.name).sorted()
            )
        }

        let scoredDevices = devices.compactMap { device -> (device: SpotifyDevice, score: Int)? in
            let normalizedDeviceName = Self.normalizeDeviceName(device.name)
            guard !normalizedDeviceName.isEmpty else {
                return nil
            }

            if normalizedDeviceName == normalizedRoomName {
                return (device, 0)
            }

            if Self.containsTokenSequence(normalizedRoomName, in: normalizedDeviceName) {
                return (device, 1)
            }

            if Self.containsTokenSequence(normalizedDeviceName, in: normalizedRoomName) {
                return (device, 2)
            }

            return nil
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.device.name < rhs.device.name
            }
            return lhs.score < rhs.score
        }

        guard let match = scoredDevices.first(where: {
            !$0.device.isRestricted && $0.device.id?.isEmpty == false
        })?.device else {
            if let restrictedMatch = scoredDevices.first?.device {
                throw SpotifyPlaybackError.restrictedDevice(restrictedMatch.name)
            }

            throw SpotifyPlaybackError.noMatchingDevice(
                roomName: roomName,
                availableDeviceNames: devices.map(\.name).sorted()
            )
        }

        return match
    }

    private static func normalizeDeviceName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\bspeaker\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsTokenSequence(_ needle: String, in haystack: String) -> Bool {
        let needleTokens = needle.split(separator: " ")
        let haystackTokens = haystack.split(separator: " ")

        guard !needleTokens.isEmpty, needleTokens.count <= haystackTokens.count else {
            return false
        }

        return haystackTokens.indices.contains { startIndex in
            let endIndex = haystackTokens.index(startIndex, offsetBy: needleTokens.count)
            guard endIndex <= haystackTokens.endIndex else {
                return false
            }
            return Array(haystackTokens[startIndex..<endIndex]) == needleTokens
        }
    }
}

extension SpotifyMusicPlaybackService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? ASPresentationAnchor()
    }
}
