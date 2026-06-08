import Foundation

struct RealSonosConfiguration: Sendable {
    let controlBaseURL: URL
    let authBrokerBaseURL: URL?
    let iosCallbackURL: URL
    let selectedHouseholdID: String?

    static func fromAppConfiguration(_ appConfiguration: AppConfiguration = .fromBundle()) -> RealSonosConfiguration {
        return RealSonosConfiguration(
            controlBaseURL: appConfiguration.sonosControlBaseURL,
            authBrokerBaseURL: appConfiguration.sonosAuthBrokerBaseURL,
            iosCallbackURL: appConfiguration.sonosCallbackURL,
            selectedHouseholdID: nil
        )
    }

    var configurationMessage: String? {
        guard controlBaseURL.scheme != nil else {
            return "SonosControlBaseURL is invalid."
        }

        guard iosCallbackURL.scheme != nil else {
            return "SonosCallbackURL is invalid."
        }

        if let authBrokerBaseURL, authBrokerBaseURL.scheme == nil {
            return "SonosAuthBrokerBaseURL is invalid."
        }

        return nil
    }

    var authenticationMessage: String {
        "Sign in to Sonos with the configured auth broker before controlling rooms."
    }

    var iosCallbackScheme: String? {
        iosCallbackURL.scheme
    }
}

@MainActor
final class RealSonosController: SonosControlling {
    private let configuration: RealSonosConfiguration
    private let tokenStore: SonosTokenStore
    private let authBrokerClient: any SonosAuthBrokerClienting
    private let topologyService: SonosTopologyService
    private let commandService: SonosCommandService

    init(
        configuration: RealSonosConfiguration = .fromAppConfiguration(),
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        authBrokerClient: (any SonosAuthBrokerClienting)? = nil
    ) {
        let tokenStore = SonosTokenStore()
        let resolvedAuthBrokerClient = authBrokerClient ?? SonosAuthBrokerClient(
            baseURL: configuration.authBrokerBaseURL,
            callbackURL: configuration.iosCallbackURL,
            session: session
        )
        let httpClient = SonosHTTPClient(
            configuration: configuration,
            session: session,
            tokenStore: tokenStore,
            refreshTokens: { refreshToken in
                try await resolvedAuthBrokerClient.refresh(refreshToken: refreshToken)
            }
        )
        let topologyService = SonosTopologyService(
            configuration: configuration,
            httpClient: httpClient,
            defaults: defaults
        )

        self.configuration = configuration
        self.tokenStore = tokenStore
        self.authBrokerClient = resolvedAuthBrokerClient
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
                return .authenticationRequired(detail)
            default:
                return .unavailable(
                    error.localizedDescription,
                    households: topologyService.cachedHouseholds,
                    selectedHouseholdID: topologyService.persistedSelectedHouseholdID()
                )
            }
        } catch {
            return .unavailable(
                error.localizedDescription,
                households: topologyService.cachedHouseholds,
                selectedHouseholdID: topologyService.persistedSelectedHouseholdID()
            )
        }
    }

    func connect() async throws -> SonosConnectionState {
        do {
            return try await validateConnection(detail: "Connected to Sonos Control API.")
        } catch let error as SonosControllerError {
            switch error {
            case .authenticationRequired:
                let tokens = try await authBrokerClient.authorize()
                tokenStore.save(tokens)
                return try await validateConnection(detail: "Sonos authorization completed.")
            default:
                throw error
            }
        }
    }

    func disconnect() async -> SonosConnectionState {
        tokenStore.delete()
        topologyService.reset()

        return .authenticationRequired(configuration.authenticationMessage)
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
        try? authBrokerClient.authorizationURL(state: UUID().uuidString)
    }

    func handleAuthorizationCallback(_ url: URL) async throws -> SonosConnectionState {
        let tokens = try await authBrokerClient.handleAuthorizationCallback(url, expectedState: nil)
        tokenStore.save(tokens)
        return try await validateConnection(detail: "Sonos authorization completed.")
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

    func groupEverywhere() async throws -> SonosCommandResult {
        try await commandService.groupEverywhere()
    }

    func playEverywhere(query: String?) async throws -> SonosCommandResult {
        try await commandService.playEverywhere(query: query)
    }

    func pauseEverywhere() async throws -> SonosCommandResult {
        try await commandService.pauseEverywhere()
    }

    private func validateConnection(detail: String) async throws -> SonosConnectionState {
        let households = try await topologyService.fetchHouseholds()
        let selectedHouseholdID = topologyService.resolveSelectedHouseholdID(from: households)
        return .ready(
            detail: detail,
            households: households,
            selectedHouseholdID: selectedHouseholdID
        )
    }
}
