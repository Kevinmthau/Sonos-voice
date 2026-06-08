import CryptoKit
import Foundation
import Security

enum SpotifyConnectionStatus: String, Codable, Sendable {
    case connected
    case authenticationRequired
    case configurationRequired
    case unavailable

    var displayName: String {
        switch self {
        case .connected:
            return "Connected"
        case .authenticationRequired:
            return "Authentication Required"
        case .configurationRequired:
            return "Configuration Required"
        case .unavailable:
            return "Unavailable"
        }
    }
}

struct SpotifyConnectionState: Equatable, Codable, Sendable {
    static let defaultAuthenticationDetail = "Sign in to Spotify to search and play tracks on Spotify Connect devices."

    let status: SpotifyConnectionStatus
    let detail: String

    var isConnected: Bool {
        status == .connected
    }

    var requiresSignIn: Bool {
        status == .authenticationRequired
    }

    static func connected(_ detail: String = "Connected to Spotify.") -> SpotifyConnectionState {
        SpotifyConnectionState(status: .connected, detail: detail)
    }

    static func authenticationRequired(_ detail: String = defaultAuthenticationDetail) -> SpotifyConnectionState {
        SpotifyConnectionState(status: .authenticationRequired, detail: detail)
    }

    static func configurationRequired(_ detail: String) -> SpotifyConnectionState {
        SpotifyConnectionState(status: .configurationRequired, detail: detail)
    }

    static func unavailable(_ detail: String) -> SpotifyConnectionState {
        SpotifyConnectionState(status: .unavailable, detail: detail)
    }
}

struct SpotifyConfiguration: Sendable {
    static let defaultCallbackURLScheme = "sonosvoiceremote"
    static let defaultAPIBaseURL = URL(string: "https://api.spotify.com/v1")!
    static let defaultAuthorizationURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let defaultTokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let requiredScopes = [
        "user-read-playback-state",
        "user-modify-playback-state"
    ]

    let apiBaseURL: URL
    let authorizationURL: URL
    let tokenURL: URL
    let redirectURL: URL
    let clientID: String?
    let scopes: [String]
    let market: String
    private let registeredCallbackURLSchemes: Set<String>

    init(
        apiBaseURL: URL,
        authorizationURL: URL,
        tokenURL: URL,
        redirectURL: URL,
        clientID: String?,
        scopes: [String],
        market: String,
        registeredCallbackURLSchemes: Set<String> = [SpotifyConfiguration.defaultCallbackURLScheme]
    ) {
        self.apiBaseURL = apiBaseURL
        self.authorizationURL = authorizationURL
        self.tokenURL = tokenURL
        self.redirectURL = redirectURL
        self.clientID = clientID
        self.scopes = scopes
        self.market = market
        self.registeredCallbackURLSchemes = Set(registeredCallbackURLSchemes.map { $0.lowercased() })
    }

    static func fromAppConfiguration(
        _ appConfiguration: AppConfiguration,
        bundle: Bundle = .main
    ) -> SpotifyConfiguration {
        SpotifyConfiguration(
            apiBaseURL: defaultAPIBaseURL,
            authorizationURL: defaultAuthorizationURL,
            tokenURL: defaultTokenURL,
            redirectURL: appConfiguration.spotifyRedirectURL,
            clientID: appConfiguration.spotifyClientID,
            scopes: requiredScopes,
            market: "US",
            registeredCallbackURLSchemes: registeredCallbackURLSchemes(in: bundle)
        )
    }

    var configurationMessage: String? {
        guard apiBaseURL.scheme != nil else {
            return "Spotify API base URL is invalid."
        }

        guard authorizationURL.scheme != nil else {
            return "Spotify authorization URL is invalid."
        }

        guard tokenURL.scheme != nil else {
            return "Spotify token URL is invalid."
        }

        guard let redirectURLScheme = redirectURL.scheme, !redirectURLScheme.isEmpty else {
            return "SpotifyRedirectURL is invalid."
        }

        guard registeredCallbackURLSchemes.contains(redirectURLScheme.lowercased()) else {
            let registeredSchemes = registeredCallbackURLSchemes.sorted().joined(separator: ", ")
            return "SpotifyRedirectURL must use a registered callback URL scheme: \(registeredSchemes)."
        }

        guard clientID?.isEmpty == false else {
            return "Set SpotifyClientID before signing in to Spotify."
        }

        return nil
    }

    var callbackURLScheme: String? {
        redirectURL.scheme
    }

    func matchesRedirectURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectURL.scheme?.lowercased()
            && (url.host ?? "").lowercased() == (redirectURL.host ?? "").lowercased()
            && url.path == redirectURL.path
    }

    private static func registeredCallbackURLSchemes(in bundle: Bundle) -> Set<String> {
        guard let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return [defaultCallbackURLScheme]
        }

        let schemes = urlTypes.flatMap { urlType -> [String] in
            urlType["CFBundleURLSchemes"] as? [String] ?? []
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty && !$0.contains("$(") }

        return schemes.isEmpty ? [defaultCallbackURLScheme] : Set(schemes)
    }
}

struct SpotifyAuthorizationRequest: Equatable, Sendable {
    let authorizationURL: URL
    let codeVerifier: String
    let state: String

    static func make(
        configuration: SpotifyConfiguration,
        codeVerifier: String? = nil,
        state: String? = nil
    ) throws -> SpotifyAuthorizationRequest {
        if let configurationMessage = configuration.configurationMessage {
            throw SpotifyPlaybackError.configurationRequired(configurationMessage)
        }

        let resolvedVerifier: String
        if let codeVerifier {
            resolvedVerifier = codeVerifier
        } else {
            resolvedVerifier = try SpotifyPKCE.makeCodeVerifier()
        }

        let resolvedState: String
        if let state {
            resolvedState = state
        } else {
            resolvedState = try SpotifyPKCE.makeState()
        }
        let codeChallenge = SpotifyPKCE.codeChallenge(for: resolvedVerifier)

        guard let clientID = configuration.clientID else {
            throw SpotifyPlaybackError.configurationRequired("Set SpotifyClientID before signing in to Spotify.")
        }

        var components = URLComponents(url: configuration.authorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURL.absoluteString),
            URLQueryItem(name: "state", value: resolvedState),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge)
        ]

        guard let authorizationURL = components?.url else {
            throw SpotifyPlaybackError.configurationRequired("Spotify authorization URL could not be built.")
        }

        return SpotifyAuthorizationRequest(
            authorizationURL: authorizationURL,
            codeVerifier: resolvedVerifier,
            state: resolvedState
        )
    }
}

enum SpotifyPKCE {
    static func makeCodeVerifier(byteCount: Int = 64) throws -> String {
        let verifier = try makeRandomBase64URLString(byteCount: byteCount)
        guard (43...128).contains(verifier.count) else {
            throw SpotifyPlaybackError.configurationRequired("Spotify PKCE code verifier length is invalid.")
        }
        return verifier
    }

    static func makeState(byteCount: Int = 32) throws -> String {
        try makeRandomBase64URLString(byteCount: byteCount)
    }

    static func codeChallenge(for codeVerifier: String) -> String {
        let digest = SHA256.hash(data: Data(codeVerifier.utf8))
        return base64URLEncoded(Data(digest))
    }

    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    private static func makeRandomBase64URLString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw SpotifyPlaybackError.configurationRequired("Secure random generation failed for Spotify authorization.")
        }
        return base64URLEncoded(Data(bytes))
    }
}

struct SpotifyStoredAuthTokens: Codable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Date?
    let scope: String?
}

struct SpotifyTrack: Equatable, Codable, Sendable {
    let id: String
    let name: String
    let uri: String
    let artists: [String]
    let isPlayable: Bool?

    init(
        id: String,
        name: String,
        uri: String,
        artists: [String],
        isPlayable: Bool? = true
    ) {
        self.id = id
        self.name = name
        self.uri = uri
        self.artists = artists
        self.isPlayable = isPlayable
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case uri
        case artists
        case isPlayable = "is_playable"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        uri = try container.decode(String.self, forKey: .uri)
        isPlayable = try container.decodeIfPresent(Bool.self, forKey: .isPlayable)
        artists = (try container.decodeIfPresent([SpotifyArtist].self, forKey: .artists) ?? []).map(\.name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(uri, forKey: .uri)
        try container.encode(artists.map { SpotifyArtist(name: $0) }, forKey: .artists)
        try container.encodeIfPresent(isPlayable, forKey: .isPlayable)
    }
}

private struct SpotifyArtist: Codable {
    let name: String
}

struct SpotifyDevice: Equatable, Codable, Sendable {
    let id: String?
    let name: String
    let type: String
    let isActive: Bool
    let isPrivateSession: Bool
    let isRestricted: Bool
    let volumePercent: Int?
    let supportsVolume: Bool

    init(
        id: String?,
        name: String,
        type: String = "speaker",
        isActive: Bool = false,
        isPrivateSession: Bool = false,
        isRestricted: Bool = false,
        volumePercent: Int? = nil,
        supportsVolume: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isActive = isActive
        self.isPrivateSession = isPrivateSession
        self.isRestricted = isRestricted
        self.volumePercent = volumePercent
        self.supportsVolume = supportsVolume
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case isActive = "is_active"
        case isPrivateSession = "is_private_session"
        case isRestricted = "is_restricted"
        case volumePercent = "volume_percent"
        case supportsVolume = "supports_volume"
    }
}

struct PreparedMusicPlayback: Equatable, Sendable {
    let query: String
    let roomName: String
    let track: SpotifyTrack
    let device: SpotifyDevice
}

struct MusicPlaybackResult: Equatable, Sendable {
    let message: String
    let trackTitle: String
    let artistName: String
    let deviceName: String
}

enum SpotifyPlaybackError: LocalizedError, Sendable {
    case noRoomSelected
    case configurationRequired(String)
    case authenticationRequired(String)
    case authorizationDenied(String)
    case invalidAuthorizationCallback(String)
    case noSearchResults(String)
    case noMatchingDevice(roomName: String, availableDeviceNames: [String])
    case restrictedDevice(String)
    case premiumRequired
    case rateLimited
    case transportFailure(String)

    var errorDescription: String? {
        switch self {
        case .noRoomSelected:
            return "Select a Sonos room before searching Spotify."
        case .configurationRequired(let message):
            return message
        case .authenticationRequired(let message):
            return message
        case .authorizationDenied(let message):
            return message
        case .invalidAuthorizationCallback(let message):
            return message
        case .noSearchResults(let query):
            return "Spotify did not find a playable track for \"\(query)\"."
        case .noMatchingDevice(let roomName, let availableDeviceNames):
            let suffix = availableDeviceNames.isEmpty ? "" : " Available devices: \(availableDeviceNames.joined(separator: ", "))."
            return "\(roomName) is not available as a Spotify Connect device. Open Spotify, choose \(roomName) from devices, then try again.\(suffix)"
        case .restrictedDevice(let deviceName):
            return "Spotify Connect says \(deviceName) is restricted. Open Spotify on that device and try again."
        case .premiumRequired:
            return "Spotify Premium is required to start playback on Spotify Connect devices."
        case .rateLimited:
            return "Spotify rate limit reached. Try again shortly."
        case .transportFailure(let message):
            return message
        }
    }
}
