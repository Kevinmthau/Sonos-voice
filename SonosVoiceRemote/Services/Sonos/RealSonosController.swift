import Foundation
import Security

private let defaultSonosClientID = "ae97b2cd-64bf-472c-9d0f-0ecac953b1dd"

struct RealSonosConfiguration {
    let controlBaseURL: URL
    let authTokenURL: URL
    let authorizationStartURL: URL?
    let iosCallbackURL: URL
    let clientID: String?
    let clientSecret: String?
    let accessToken: String?
    let refreshToken: String?
    let selectedHouseholdID: String?

    static func fromEnvironment() -> RealSonosConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let defaultControlBaseURL = URL(string: "https://api.ws.sonos.com/control/api/v1")!
        let defaultAuthTokenURL = URL(string: "https://api.sonos.com/login/v3/oauth/access")!
        let defaultAuthorizationStartURL = URL(string: "https://sonos-voice.netlify.app/sonos/oauth/start")
        let defaultIOSCallbackURL = URL(string: "sonosvoiceremote://oauth/callback")!

        let controlBaseURL = environment["SONOS_CONTROL_API_BASE_URL"]
            .flatMap(URL.init(string:))
            ?? environment["SONOS_API_BASE_URL"].flatMap(URL.init(string:))
            ?? defaultControlBaseURL

        let authTokenURL = environment["SONOS_AUTH_TOKEN_URL"].flatMap(URL.init(string:)) ?? defaultAuthTokenURL
        let authorizationStartURL = environment["SONOS_AUTH_START_URL"]
            .flatMap(URL.init(string:))
            ?? defaultAuthorizationStartURL
        let iosCallbackURL = environment["SONOS_IOS_CALLBACK_URL"]
            .flatMap(URL.init(string:))
            ?? defaultIOSCallbackURL

        return RealSonosConfiguration(
            controlBaseURL: controlBaseURL,
            authTokenURL: authTokenURL,
            authorizationStartURL: authorizationStartURL,
            iosCallbackURL: iosCallbackURL,
            clientID: environment["SONOS_CLIENT_ID"] ?? defaultSonosClientID,
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
}

private struct StoredAuthTokens: Codable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Date?
}

private struct SonosAPIHouseholdsResponse: Decodable {
    let households: [SonosAPIHousehold]
}

private struct SonosAPIHousehold: Decodable {
    let id: String?
    let householdId: String?
    let name: String?

    var resolvedID: String? {
        id ?? householdId
    }

    var displayName: String {
        name ?? resolvedID ?? "Sonos Household"
    }
}

private struct SonosAPIGroupsResponse: Decodable {
    let players: [SonosAPIPlayer]
    let groups: [SonosAPIGroup]
}

private struct SonosAPIPlayer: Decodable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case playerName
        case roomName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .playerName)
            ?? container.decodeIfPresent(String.self, forKey: .roomName)
            ?? "Room \(id.prefix(6))"
    }
}

private struct SonosAPIGroup: Decodable {
    let id: String
    let name: String?
    let coordinatorId: String?
    let playerIds: [String]
    let playbackState: String?

    var displayName: String {
        name ?? "Sonos Group"
    }

    var isPlaying: Bool {
        guard let playbackState else { return false }
        let normalized = playbackState.uppercased()
        return normalized.contains("PLAYING") || normalized.contains("BUFFERING")
    }
}

private struct SonosAPIPlayerVolumeResponse: Decodable {
    let volume: Int?
}

private struct SonosAPINamedItemsResponse: Decodable {
    let items: [SonosAPINamedItem]

    enum CodingKeys: String, CodingKey {
        case items
        case favorites
        case playlists
    }

    init(from decoder: Decoder) throws {
        if let array = try? [SonosAPINamedItem](from: decoder) {
            items = array
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([SonosAPINamedItem].self, forKey: .items)
            ?? container.decodeIfPresent([SonosAPINamedItem].self, forKey: .favorites)
            ?? container.decodeIfPresent([SonosAPINamedItem].self, forKey: .playlists)
            ?? []
    }
}

private struct SonosAPINamedItem: Decodable {
    let id: String?
    let favoriteId: String?
    let playlistId: String?
    let name: String?
    let title: String?

    var resolvedID: String? {
        favoriteId ?? playlistId ?? id
    }

    var displayName: String {
        name ?? title ?? resolvedID ?? "Untitled"
    }
}

private struct SonosAPIErrorResponse: Decodable {
    let message: String?
    let error: String?
    let reason: String?

    var detail: String? {
        message ?? error ?? reason
    }
}

private struct CreateGroupRequest: Encodable {
    let playerIds: [String]
}

private struct SetVolumeRequest: Encodable {
    let volume: Int
}

private struct RelativeVolumeRequest: Encodable {
    let volumeDelta: Int
}

private struct LoadFavoriteRequest: Encodable {
    let favoriteId: String
    let queueAction: String
}

private struct LoadPlaylistRequest: Encodable {
    let playlistId: String
    let queueAction: String
}

private struct SonosEmptyResponse: Decodable { }

private struct SonosTopology {
    let household: SonosHousehold
    let rooms: [SonosRoom]
}

private enum ResolvedQueueContent {
    case favorite(id: String, name: String)
    case playlist(id: String, name: String)

    var displayName: String {
        switch self {
        case .favorite(_, let name), .playlist(_, let name):
            return name
        }
    }
}

private struct SonosTokenKeychain {
    private let service = "com.kevinthau.SonosVoiceRemote.sonos"
    private let account = "oauth-tokens"

    func load() -> StoredAuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(StoredAuthTokens.self, from: data)
    }

    func save(_ tokens: StoredAuthTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else {
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}

actor RealSonosController: SonosControlling {
    private let configuration: RealSonosConfiguration
    private let session: URLSession
    private let keychain = SonosTokenKeychain()
    private let defaults: UserDefaults
    private let householdSelectionKey = "SonosVoiceRemote.selectedHouseholdID"

    private var cachedHouseholds: [SonosHousehold] = []
    private var lastKnownRooms: [SonosRoom] = []

    init(
        configuration: RealSonosConfiguration = .fromEnvironment(),
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.session = session
        self.defaults = defaults
    }

    func connectionState() async -> SonosConnectionState {
        if let configurationMessage = configuration.configurationMessage {
            return .configurationRequired(configurationMessage)
        }

        do {
            let households = try await fetchHouseholds()
            let selectedHouseholdID = resolveSelectedHouseholdID(from: households)
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
                    households: cachedHouseholds,
                    selectedHouseholdID: persistedSelectedHouseholdID(),
                    authorizationURL: configuration.authorizationStartURL
                )
            }
        } catch {
            return .unavailable(
                error.localizedDescription,
                households: cachedHouseholds,
                selectedHouseholdID: persistedSelectedHouseholdID(),
                authorizationURL: configuration.authorizationStartURL
            )
        }
    }

    func connect() async throws -> SonosConnectionState {
        let households = try await fetchHouseholds()
        let selectedHouseholdID = resolveSelectedHouseholdID(from: households)
        return .ready(
            detail: "Connected to Sonos Control API.",
            households: households,
            selectedHouseholdID: selectedHouseholdID
        )
    }

    func disconnect() async -> SonosConnectionState {
        keychain.delete()
        cachedHouseholds = []
        lastKnownRooms = []
        defaults.removeObject(forKey: householdSelectionKey)

        if configuration.accessToken?.isEmpty == false || configuration.refreshToken?.isEmpty == false {
            return .authenticationRequired(
                "Environment-provided Sonos credentials remain available. Remove them to fully disconnect.",
                authorizationURL: configuration.authorizationStartURL
            )
        }

        return .authenticationRequired(configuration.authenticationMessage, authorizationURL: configuration.authorizationStartURL)
    }

    func selectHousehold(id: String) async throws -> SonosConnectionState {
        let households = try await fetchHouseholds()
        guard households.contains(where: { $0.id == id }) else {
            throw SonosControllerError.householdNotFound(id)
        }

        persistSelectedHouseholdID(id)
        cachedHouseholds = households
        _ = try await discoverRooms()
        return .ready(
            detail: "Selected Sonos household \(households.first(where: { $0.id == id })?.name ?? id).",
            households: cachedHouseholds,
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

        keychain.save(
            StoredAuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresIn > 0 ? Date().addingTimeInterval(TimeInterval(expiresIn)) : nil
            )
        )

        return try await connect()
    }

    func discoverRooms() async throws -> [SonosRoom] {
        let topology = try await fetchTopology()
        lastKnownRooms = topology.rooms.sorted { $0.name < $1.name }
        cachedHouseholds = merge(topology.household, into: cachedHouseholds)
        return lastKnownRooms
    }

    func play(room: SonosRoom?, query: String?) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        guard let groupID = target.groupID else {
            throw SonosControllerError.transportFailure("The selected Sonos room is missing a group identifier.")
        }

        let message: String
        if let query = sanitized(query) {
            let content = try await resolveQueueContent(named: query, householdID: try resolveHouseholdID(for: target))
            try await load(content, ontoGroupID: groupID)
            message = "Loaded \(content.displayName) in \(target.name)."
        } else {
            try await sendNoContent(path: "groups/\(groupID)/playback/play", method: "POST")
            message = "Resumed playback in \(target.name)."
        }

        let updatedRooms = try await discoverRooms()
        return SonosCommandResult(message: message, updatedRooms: annotated(updatedRooms, query: query, roomName: target.name))
    }

    func pause(room: SonosRoom?) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        guard let groupID = target.groupID else {
            throw SonosControllerError.transportFailure("The selected Sonos room is missing a group identifier.")
        }

        try await sendNoContent(path: "groups/\(groupID)/playback/pause", method: "POST")
        let updatedRooms = try await discoverRooms()
        return SonosCommandResult(message: "Paused \(target.name).", updatedRooms: updatedRooms)
    }

    func resume(room: SonosRoom?) async throws -> SonosCommandResult {
        try await play(room: room, query: nil)
    }

    func skip(room: SonosRoom?) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        guard let groupID = target.groupID else {
            throw SonosControllerError.transportFailure("The selected Sonos room is missing a group identifier.")
        }

        try await sendNoContent(path: "groups/\(groupID)/playback/skipToNextTrack", method: "POST")
        let updatedRooms = try await discoverRooms()
        return SonosCommandResult(message: "Skipped in \(target.name).", updatedRooms: updatedRooms)
    }

    func setVolume(room: SonosRoom?, value: Int) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        guard let playerID = target.playerID else {
            throw SonosControllerError.transportFailure("The selected Sonos room is missing a player identifier.")
        }

        let clampedValue = max(0, min(100, value))
        try await sendNoContent(
            path: "players/\(playerID)/playerVolume",
            method: "POST",
            body: SetVolumeRequest(volume: clampedValue)
        )

        let updatedRooms = try await discoverRooms()
        return SonosCommandResult(message: "Set \(target.name) to volume \(clampedValue).", updatedRooms: updatedRooms)
    }

    func volumeUp(room: SonosRoom?) async throws -> SonosCommandResult {
        try await adjustVolume(room: room, delta: 5, verb: "Raised")
    }

    func volumeDown(room: SonosRoom?) async throws -> SonosCommandResult {
        try await adjustVolume(room: room, delta: -5, verb: "Lowered")
    }

    func playEverywhere(query: String?) async throws -> SonosCommandResult {
        let topology = try await fetchTopology()
        let playerIDs = topology.rooms.compactMap(\.playerID)
        guard !playerIDs.isEmpty else {
            throw SonosControllerError.transportFailure("No Sonos players were discovered in the selected household.")
        }

        let queueContent: ResolvedQueueContent?
        if let query = sanitized(query) {
            queueContent = try await resolveQueueContent(named: query, householdID: topology.household.id)
        } else {
            queueContent = nil
        }

        let groupID = try await createGroup(householdID: topology.household.id, playerIDs: playerIDs)

        let message: String
        if let queueContent {
            try await load(queueContent, ontoGroupID: groupID)
            message = "Grouped all rooms and loaded \(queueContent.displayName)."
        } else {
            try await sendNoContent(path: "groups/\(groupID)/playback/play", method: "POST")
            message = "Grouped all rooms and resumed playback."
        }

        let updatedRooms = try await discoverRooms()
        return SonosCommandResult(message: message, updatedRooms: annotated(updatedRooms, query: query, roomName: nil))
    }

    func pauseEverywhere() async throws -> SonosCommandResult {
        let topology = try await fetchTopology()
        let groupIDs = Set(topology.rooms.compactMap(\.groupID))

        for groupID in groupIDs {
            try await sendNoContent(path: "groups/\(groupID)/playback/pause", method: "POST")
        }

        let updatedRooms = try await discoverRooms()
        return SonosCommandResult(message: "Paused playback across the selected Sonos household.", updatedRooms: updatedRooms)
    }

    private func adjustVolume(room: SonosRoom?, delta: Int, verb: String) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        guard let playerID = target.playerID else {
            throw SonosControllerError.transportFailure("The selected Sonos room is missing a player identifier.")
        }

        try await sendNoContent(
            path: "players/\(playerID)/playerVolume/relative",
            method: "POST",
            body: RelativeVolumeRequest(volumeDelta: delta)
        )

        let updatedRooms = try await discoverRooms()
        let resolvedTarget = updatedRooms.first(where: { $0.id == target.id }) ?? target
        return SonosCommandResult(message: "\(verb) \(target.name) to \(resolvedTarget.volume).", updatedRooms: updatedRooms)
    }

    private func fetchHouseholds() async throws -> [SonosHousehold] {
        if let configurationMessage = configuration.configurationMessage {
            throw SonosControllerError.notConfigured(configurationMessage)
        }

        let response: SonosAPIHouseholdsResponse = try await send(path: "households", method: "GET")
        let households = response.households.compactMap { household -> SonosHousehold? in
            guard let id = household.resolvedID else {
                return nil
            }

            let existingRooms = cachedHouseholds.first(where: { $0.id == id })?.roomNames ?? []
            return SonosHousehold(id: id, name: household.displayName, roomNames: existingRooms)
        }

        guard !households.isEmpty else {
            throw SonosControllerError.transportFailure("Sonos did not return any households for the current account.")
        }

        cachedHouseholds = households
        return households
    }

    private func fetchTopology() async throws -> SonosTopology {
        let households = try await fetchHouseholds()
        let householdID = resolveSelectedHouseholdID(from: households)
        let response: SonosAPIGroupsResponse = try await send(
            path: "households/\(householdID)/groups",
            method: "GET"
        )

        var rooms: [SonosRoom] = []
        rooms.reserveCapacity(response.players.count)
        for player in response.players {
            let matchingGroup = response.groups.first(where: { $0.playerIds.contains(player.id) })
            let volume = try await fetchVolume(for: player.id)
            rooms.append(
                SonosRoom(
                id: player.id,
                name: player.name,
                playerID: player.id,
                groupID: matchingGroup?.id,
                householdID: householdID,
                volume: volume,
                isCoordinator: matchingGroup?.coordinatorId == player.id,
                groupName: matchingGroup?.displayName,
                isPlaying: matchingGroup?.isPlaying ?? false,
                currentContent: lastKnownRooms.first(where: { $0.id == player.id })?.currentContent
            )
            )
        }

        let baseHousehold = households.first(where: { $0.id == householdID })
            ?? SonosHousehold(id: householdID, name: householdID, roomNames: [])

        return SonosTopology(
            household: SonosHousehold(
                id: baseHousehold.id,
                name: baseHousehold.name,
                roomNames: rooms.map(\.name).sorted()
            ),
            rooms: rooms.sorted { $0.name < $1.name }
        )
    }

    private func fetchVolume(for playerID: String) async throws -> Int {
        do {
            let response: SonosAPIPlayerVolumeResponse = try await send(
                path: "players/\(playerID)/playerVolume",
                method: "GET"
            )
            return max(0, min(100, response.volume ?? 20))
        } catch {
            return lastKnownRooms.first(where: { $0.playerID == playerID })?.volume ?? 20
        }
    }

    private func createGroup(householdID: String, playerIDs: [String]) async throws -> String {
        try await sendNoContent(
            path: "households/\(householdID)/groups/createGroup",
            method: "POST",
            body: CreateGroupRequest(playerIds: playerIDs)
        )

        let response: SonosAPIGroupsResponse = try await send(
            path: "households/\(householdID)/groups",
            method: "GET"
        )

        let requestedIDs = Set(playerIDs)
        guard let createdGroup = response.groups.first(where: { Set($0.playerIds) == requestedIDs }) else {
            throw SonosControllerError.transportFailure("Sonos accepted the group request, but the new group could not be resolved.")
        }

        return createdGroup.id
    }

    private func resolveQueueContent(named query: String, householdID: String) async throws -> ResolvedQueueContent {
        let normalizedQuery = normalize(query)

        let favorites: SonosAPINamedItemsResponse = try await send(
            path: "households/\(householdID)/favorites",
            method: "GET"
        )
        if let favorite = bestMatch(for: normalizedQuery, in: favorites.items) {
            return .favorite(id: favorite.resolvedID ?? favorite.displayName, name: favorite.displayName)
        }

        let playlists: SonosAPINamedItemsResponse = try await send(
            path: "households/\(householdID)/playlists",
            method: "GET"
        )
        if let playlist = bestMatch(for: normalizedQuery, in: playlists.items) {
            return .playlist(id: playlist.resolvedID ?? playlist.displayName, name: playlist.displayName)
        }

        // TODO: Replace this favorites/playlists lookup with a proper content-service or search backend for free-form requests.
        throw SonosControllerError.unsupported(
            "The real Sonos path can load Sonos favorites and playlists here, but arbitrary search queries like \"\(query)\" still need a content-service integration."
        )
    }

    private func load(_ content: ResolvedQueueContent, ontoGroupID groupID: String) async throws {
        switch content {
        case .favorite(let id, _):
            try await sendNoContent(
                path: "groups/\(groupID)/favorites/loadFavorite",
                method: "POST",
                body: LoadFavoriteRequest(favoriteId: id, queueAction: "REPLACE")
            )

        case .playlist(let id, _):
            try await sendNoContent(
                path: "groups/\(groupID)/playlists/loadPlaylist",
                method: "POST",
                body: LoadPlaylistRequest(playlistId: id, queueAction: "REPLACE")
            )
        }
    }

    private func bestMatch(for normalizedQuery: String, in items: [SonosAPINamedItem]) -> SonosAPINamedItem? {
        let exact = items.first(where: {
            guard let id = $0.resolvedID else { return false }
            return normalize($0.displayName) == normalizedQuery && !id.isEmpty
        })

        if let exact {
            return exact
        }

        return items.first(where: {
            guard let id = $0.resolvedID else { return false }
            let candidate = normalize($0.displayName)
            return !id.isEmpty && (candidate.contains(normalizedQuery) || normalizedQuery.contains(candidate))
        })
    }

    private func resolveRoom(from room: SonosRoom?) throws -> SonosRoom {
        guard let room else {
            throw SonosControllerError.noRoomSelected
        }

        if let resolved = lastKnownRooms.first(where: { $0.id == room.id }) {
            return resolved
        }

        return room
    }

    private func resolveHouseholdID(for room: SonosRoom) throws -> String {
        if let householdID = room.householdID {
            return householdID
        }

        if let selectedHouseholdID = persistedSelectedHouseholdID() {
            return selectedHouseholdID
        }

        throw SonosControllerError.transportFailure("The selected Sonos room is missing a household identifier.")
    }

    private func merge(_ household: SonosHousehold, into households: [SonosHousehold]) -> [SonosHousehold] {
        let filtered = households.filter { $0.id != household.id }
        return (filtered + [household]).sorted { $0.name < $1.name }
    }

    private func annotated(_ rooms: [SonosRoom], query: String?, roomName: String?) -> [SonosRoom] {
        guard let query = sanitized(query) else {
            return rooms
        }

        return rooms.map { room in
            var updated = room
            if roomName == nil || room.name.caseInsensitiveCompare(roomName ?? "") == .orderedSame {
                updated.currentContent = query.capitalized
            }
            return updated
        }
    }

    private func sanitized(_ query: String?) -> String? {
        guard let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendNoContent(path: String, method: String) async throws {
        let _: SonosEmptyResponse = try await send(path: path, method: method)
    }

    private func sendNoContent<Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws {
        let _: SonosEmptyResponse = try await send(path: path, method: method, body: body)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String
    ) async throws -> Response {
        try await send(path: path, method: method, bodyData: nil)
    }

    private func send<Response: Decodable, Body: Encodable>(
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

        if let clientID = configuration.clientID, !clientID.isEmpty {
            request.setValue(clientID, forHTTPHeaderField: "X-Sonos-Api-Key")
        }

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

        guard
            let clientID = configuration.clientID, !clientID.isEmpty,
            let clientSecret = configuration.clientSecret, !clientSecret.isEmpty
        else {
            throw SonosControllerError.notConfigured(configuration.refreshConfigurationMessage)
        }

        var request = URLRequest(url: configuration.authTokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        let refreshBody = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        request.httpBody = refreshBody
            .compactMap { item in
                guard let value = item.value else { return nil }
                return "\(item.name)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            let detail = (try? JSONDecoder().decode(SonosAPIErrorResponse.self, from: data).detail)
                ?? "The Sonos token refresh request failed."
            throw SonosControllerError.authenticationRequired(detail)
        }

        let tokenResponse = try JSONDecoder().decode(SonosOAuthTokenResponse.self, from: data)
        keychain.save(
            StoredAuthTokens(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken ?? refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            )
        )
        return true
    }

    private func currentTokens() -> StoredAuthTokens {
        let storedTokens = keychain.load() ?? StoredAuthTokens(accessToken: nil, refreshToken: nil, expiresAt: nil)

        return StoredAuthTokens(
            accessToken: configuration.accessToken ?? storedTokens.accessToken,
            refreshToken: configuration.refreshToken ?? storedTokens.refreshToken,
            expiresAt: configuration.accessToken == nil ? storedTokens.expiresAt : nil
        )
    }

    private func resolveSelectedHouseholdID(from households: [SonosHousehold]) -> String {
        let candidates = [
            configuration.selectedHouseholdID,
            persistedSelectedHouseholdID(),
            households.first?.id
        ]

        let resolvedID = candidates.compactMap { $0 }.first(where: { candidate in
            households.contains(where: { $0.id == candidate })
        }) ?? households[0].id

        persistSelectedHouseholdID(resolvedID)
        return resolvedID
    }

    private func persistedSelectedHouseholdID() -> String? {
        defaults.string(forKey: householdSelectionKey)
    }

    private func persistSelectedHouseholdID(_ householdID: String) {
        defaults.set(householdID, forKey: householdSelectionKey)
    }
}

private struct SonosOAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
