import Foundation

final class SonosTopologyService {
    private let configuration: RealSonosConfiguration
    private let httpClient: SonosHTTPClient
    private let defaults: UserDefaults
    private let householdSelectionKey = "SonosVoiceRemote.selectedHouseholdID"

    private(set) var cachedHouseholds: [SonosHousehold] = []
    private(set) var lastKnownRooms: [SonosRoom] = []

    init(
        configuration: RealSonosConfiguration,
        httpClient: SonosHTTPClient,
        defaults: UserDefaults
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.defaults = defaults
    }

    func reset() {
        cachedHouseholds = []
        lastKnownRooms = []
        defaults.removeObject(forKey: householdSelectionKey)
    }

    func fetchHouseholds() async throws -> [SonosHousehold] {
        if let configurationMessage = configuration.configurationMessage {
            throw SonosControllerError.notConfigured(configurationMessage)
        }

        let response: SonosAPIHouseholdsResponse = try await httpClient.send(path: "households", method: "GET")
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

    func discoverRooms() async throws -> [SonosRoom] {
        let topology = try await fetchTopology()
        lastKnownRooms = topology.rooms.sorted { $0.name < $1.name }
        cachedHouseholds = merge(topology.household, into: cachedHouseholds)
        return lastKnownRooms
    }

    func fetchTopology() async throws -> SonosTopology {
        let households = try await fetchHouseholds()
        let householdID = resolveSelectedHouseholdID(from: households)
        let response: SonosAPIGroupsResponse = try await httpClient.send(
            path: "households/\(householdID)/groups",
            method: "GET"
        )

        let lastRooms = lastKnownRooms
        let volumeByPlayerID = await fetchVolumes(
            for: response.players.map(\.id),
            lastKnownRooms: lastRooms
        )

        let rooms = response.players.map { player in
            let matchingGroup = response.groups.first(where: { $0.playerIds.contains(player.id) })
            return SonosRoom(
                id: player.id,
                name: player.name,
                playerID: player.id,
                groupID: matchingGroup?.id,
                householdID: householdID,
                volume: volumeByPlayerID[player.id] ?? 20,
                isCoordinator: matchingGroup?.coordinatorId == player.id,
                groupName: matchingGroup?.displayName,
                isPlaying: matchingGroup?.isPlaying ?? false,
                currentContent: lastRooms.first(where: { $0.id == player.id })?.currentContent
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

    func resolveSelectedHouseholdID(from households: [SonosHousehold]) -> String {
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

    func persistedSelectedHouseholdID() -> String? {
        defaults.string(forKey: householdSelectionKey)
    }

    func persistSelectedHouseholdID(_ householdID: String) {
        defaults.set(householdID, forKey: householdSelectionKey)
    }

    private func fetchVolumes(for playerIDs: [String], lastKnownRooms: [SonosRoom]) async -> [String: Int] {
        await withTaskGroup(of: (String, Int).self, returning: [String: Int].self) { group in
            for playerID in playerIDs {
                group.addTask {
                    do {
                        let response: SonosAPIPlayerVolumeResponse = try await self.httpClient.send(
                            path: "players/\(playerID)/playerVolume",
                            method: "GET"
                        )
                        return (playerID, max(0, min(100, response.volume ?? 20)))
                    } catch {
                        let fallback = lastKnownRooms.first(where: { $0.playerID == playerID })?.volume ?? 20
                        return (playerID, fallback)
                    }
                }
            }

            var volumeByPlayerID: [String: Int] = [:]
            for await (playerID, volume) in group {
                volumeByPlayerID[playerID] = volume
            }
            return volumeByPlayerID
        }
    }

    private func merge(_ household: SonosHousehold, into households: [SonosHousehold]) -> [SonosHousehold] {
        let filtered = households.filter { $0.id != household.id }
        return (filtered + [household]).sorted { $0.name < $1.name }
    }
}
