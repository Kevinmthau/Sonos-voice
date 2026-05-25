import Foundation

struct RealSonosConfiguration: Sendable {
    let controlBaseURL: URL
    let authTokenURL: URL
    let authorizationStartURL: URL?
    let iosCallbackURL: URL
    let clientID: String?
    let clientSecret: String?
    let accessToken: String?
    let refreshToken: String?
    let selectedHouseholdID: String?

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> RealSonosConfiguration {
        let defaultControlBaseURL = URL(string: "https://api.ws.sonos.com/control/api/v1")!
        let defaultAuthTokenURL = URL(string: "https://api.sonos.com/login/v3/oauth/access")!
        let defaultIOSCallbackURL = URL(string: "sonosvoiceremote://oauth/callback")!

        let controlBaseURL = environment["SONOS_CONTROL_API_BASE_URL"]
            .flatMap(URL.init(string:))
            ?? environment["SONOS_API_BASE_URL"].flatMap(URL.init(string:))
            ?? defaultControlBaseURL

        let authTokenURL = environment["SONOS_AUTH_TOKEN_URL"].flatMap(URL.init(string:)) ?? defaultAuthTokenURL
        let authorizationStartURL = environment["SONOS_AUTH_START_URL"]
            .flatMap(URL.init(string:))
            ?? configuredString("SonosAuthorizationStartURL", bundle: bundle).flatMap(URL.init(string:))
        let iosCallbackURL = environment["SONOS_IOS_CALLBACK_URL"]
            .flatMap(URL.init(string:))
            ?? defaultIOSCallbackURL

        return RealSonosConfiguration(
            controlBaseURL: controlBaseURL,
            authTokenURL: authTokenURL,
            authorizationStartURL: authorizationStartURL,
            iosCallbackURL: iosCallbackURL,
            clientID: environment["SONOS_CLIENT_ID"] ?? configuredString("SonosClientID", bundle: bundle),
            clientSecret: environment["SONOS_CLIENT_SECRET"],
            accessToken: environment["SONOS_ACCESS_TOKEN"],
            refreshToken: environment["SONOS_REFRESH_TOKEN"],
            selectedHouseholdID: environment["SONOS_HOUSEHOLD_ID"]
        )
    }

    var configurationMessage: String? {
        guard controlBaseURL.scheme != nil else {
            return "SONOS_CONTROL_API_BASE_URL is invalid."
        }

        guard authTokenURL.scheme != nil else {
            return "SONOS_AUTH_TOKEN_URL is invalid."
        }

        if let authorizationStartURL, authorizationStartURL.scheme == nil {
            return "SONOS_AUTH_START_URL is invalid."
        }

        guard iosCallbackURL.scheme != nil else {
            return "SONOS_IOS_CALLBACK_URL is invalid."
        }

        return nil
    }

    var authenticationMessage: String {
        let hasAccessToken = accessToken?.isEmpty == false
        let hasRefreshPath = refreshToken?.isEmpty == false && clientID?.isEmpty == false && clientSecret?.isEmpty == false

        if hasAccessToken || hasRefreshPath {
            return "Sonos credentials are available, but authentication still needs to be validated."
        }

        return """
        SonosVoiceRemote needs Sonos credentials. Tap the Sonos sign-in link, or set SONOS_ACCESS_TOKEN, or set SONOS_REFRESH_TOKEN together with SONOS_CLIENT_ID and SONOS_CLIENT_SECRET.
        """
    }

    var refreshConfigurationMessage: String {
        """
        Refreshing Sonos tokens requires SONOS_REFRESH_TOKEN, SONOS_CLIENT_ID, and SONOS_CLIENT_SECRET. TODO: move this exchange to a secure backend before shipping.
        """
    }

    var iosCallbackScheme: String? {
        iosCallbackURL.scheme
    }

    private static func configuredString(_ key: String, bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }
}

actor RealSonosController: SonosControlling {
    private let configuration: RealSonosConfiguration
    private let tokenStore: SonosTokenStore
    private let topologyService: SonosTopologyService
    private let commandService: SonosCommandService

    init(
        configuration: RealSonosConfiguration = .fromEnvironment(),
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        let tokenStore = SonosTokenStore()
        let httpClient = SonosHTTPClient(configuration: configuration, session: session, tokenStore: tokenStore)
        let topologyService = SonosTopologyService(
            configuration: configuration,
            httpClient: httpClient,
            defaults: defaults
        )

        self.configuration = configuration
        self.tokenStore = tokenStore
        self.topologyService = topologyService
        self.commandService = SonosCommandService(httpClient: httpClient, topologyService: topologyService)
    }

    func connectionState() async -> SonosConnectionState {
        if let configurationMessage = configuration.configurationMessage {
            return .configurationRequired(configurationMessage)
        }

        do {
            let households = try await topologyService.fetchHouseholds()
            let selectedHouseholdID = topologyService.resolveSelectedHouseholdID(from: households)
            return .ready(
                detail: "Connected to Sonos Control API.",
                households: households,
                selectedHouseholdID: selectedHouseholdID
            )
        } catch let error as SonosControllerError {
            switch error {
            case .notConfigured(let detail):
                return .configurationRequired(detail)
            case .authenticationRequired(let detail):
                return .authenticationRequired(detail, authorizationURL: configuration.authorizationStartURL)
            default:
                return .unavailable(
                    error.localizedDescription,
                    households: topologyService.cachedHouseholds,
                    selectedHouseholdID: topologyService.persistedSelectedHouseholdID(),
                    authorizationURL: configuration.authorizationStartURL
                )
            }
        } catch {
            return .unavailable(
                error.localizedDescription,
                households: topologyService.cachedHouseholds,
                selectedHouseholdID: topologyService.persistedSelectedHouseholdID(),
                authorizationURL: configuration.authorizationStartURL
            )
        }
    }

    func connect() async throws -> SonosConnectionState {
        let households = try await topologyService.fetchHouseholds()
        let selectedHouseholdID = topologyService.resolveSelectedHouseholdID(from: households)
        return .ready(
            detail: "Connected to Sonos Control API.",
            households: households,
            selectedHouseholdID: selectedHouseholdID
        )
    }

    func disconnect() async -> SonosConnectionState {
        tokenStore.delete()
        topologyService.reset()

        if configuration.accessToken?.isEmpty == false || configuration.refreshToken?.isEmpty == false {
            return .authenticationRequired(
                "Environment-provided Sonos credentials remain available. Remove them to fully disconnect.",
                authorizationURL: configuration.authorizationStartURL
            )
        }

        return .authenticationRequired(configuration.authenticationMessage, authorizationURL: configuration.authorizationStartURL)
    }

    func selectHousehold(id: String) async throws -> SonosConnectionState {
        let households = try await topologyService.fetchHouseholds()
        guard households.contains(where: { $0.id == id }) else {
            throw SonosControllerError.householdNotFound(id)
        }

        topologyService.persistSelectedHouseholdID(id)
        _ = try await topologyService.discoverRooms()
        return .ready(
            detail: "Selected Sonos household \(households.first(where: { $0.id == id })?.name ?? id).",
            households: topologyService.cachedHouseholds,
            selectedHouseholdID: id
        )
    }

    func authorizationURL() async -> URL? {
        configuration.authorizationStartURL
    }

    func handleAuthorizationCallback(_ url: URL) async throws -> SonosConnectionState {
        guard let expectedScheme = configuration.iosCallbackScheme?.lowercased() else {
            throw SonosControllerError.notConfigured("SONOS_IOS_CALLBACK_URL is invalid.")
        }

        guard url.scheme?.lowercased() == expectedScheme else {
            throw SonosControllerError.transportFailure("Received an unexpected OAuth callback URL.")
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        if let error = items.first(where: { $0.name == "error" })?.value {
            let description = items.first(where: { $0.name == "error_description" })?.value ?? error
            throw SonosControllerError.authenticationRequired(description)
        }

        let accessToken = items.first(where: { $0.name == "access_token" })?.value
        let refreshToken = items.first(where: { $0.name == "refresh_token" })?.value
        let expiresIn = items.first(where: { $0.name == "expires_in" })?.value.flatMap(Int.init) ?? 0

        guard let accessToken, !accessToken.isEmpty else {
            throw SonosControllerError.authenticationRequired("The Sonos callback did not include an access token.")
        }

        tokenStore.save(
            StoredAuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresIn > 0 ? Date().addingTimeInterval(TimeInterval(expiresIn)) : nil
            )
        )

        return try await connect()
    }

    func discoverRooms() async throws -> [SonosRoom] {
        try await topologyService.discoverRooms()
    }

    func play(room: SonosRoom?, query: String?) async throws -> SonosCommandResult {
        try await commandService.play(room: room, query: query)
    }

    func pause(room: SonosRoom?) async throws -> SonosCommandResult {
        try await commandService.pause(room: room)
    }

    func resume(room: SonosRoom?) async throws -> SonosCommandResult {
        try await commandService.resume(room: room)
    }

    func skip(room: SonosRoom?) async throws -> SonosCommandResult {
        try await commandService.skip(room: room)
    }

    func setVolume(room: SonosRoom?, value: Int) async throws -> SonosCommandResult {
        try await commandService.setVolume(room: room, value: value)
    }

    func volumeUp(room: SonosRoom?) async throws -> SonosCommandResult {
        try await commandService.volumeUp(room: room)
    }

    func volumeDown(room: SonosRoom?) async throws -> SonosCommandResult {
        try await commandService.volumeDown(room: room)
    }

    func playEverywhere(query: String?) async throws -> SonosCommandResult {
        try await commandService.playEverywhere(query: query)
    }

    func pauseEverywhere() async throws -> SonosCommandResult {
        try await commandService.pauseEverywhere()
    }
}
