import Foundation

final class SonosCommandService {
    private let httpClient: SonosHTTPClient
    private let topologyService: SonosTopologyService

    init(httpClient: SonosHTTPClient, topologyService: SonosTopologyService) {
        self.httpClient = httpClient
        self.topologyService = topologyService
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
            try await httpClient.sendNoContent(path: "groups/\(groupID)/playback/play", method: "POST")
            message = "Resumed playback in \(target.name)."
        }

        let updatedRooms = try await topologyService.discoverRooms()
        return SonosCommandResult(message: message, updatedRooms: annotated(updatedRooms, query: query, roomName: target.name))
    }

    func pause(room: SonosRoom?) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        guard let groupID = target.groupID else {
            throw SonosControllerError.transportFailure("The selected Sonos room is missing a group identifier.")
        }

        try await httpClient.sendNoContent(path: "groups/\(groupID)/playback/pause", method: "POST")
        let updatedRooms = try await topologyService.discoverRooms()
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

        try await httpClient.sendNoContent(path: "groups/\(groupID)/playback/skipToNextTrack", method: "POST")
        let updatedRooms = try await topologyService.discoverRooms()
        return SonosCommandResult(message: "Skipped in \(target.name).", updatedRooms: updatedRooms)
    }

    func setVolume(room: SonosRoom?, value: Int) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        guard let playerID = target.playerID else {
            throw SonosControllerError.transportFailure("The selected Sonos room is missing a player identifier.")
        }

        let clampedValue = max(0, min(100, value))
        try await httpClient.sendNoContent(
            path: "players/\(playerID)/playerVolume",
            method: "POST",
            body: SetVolumeRequest(volume: clampedValue)
        )

        let updatedRooms = try await topologyService.discoverRooms()
        return SonosCommandResult(message: "Set \(target.name) to volume \(clampedValue).", updatedRooms: updatedRooms)
    }

    func volumeUp(room: SonosRoom?) async throws -> SonosCommandResult {
        try await adjustVolume(room: room, delta: 5, verb: "Raised")
    }

    func volumeDown(room: SonosRoom?) async throws -> SonosCommandResult {
        try await adjustVolume(room: room, delta: -5, verb: "Lowered")
    }

    func playEverywhere(query: String?) async throws -> SonosCommandResult {
        let topology = try await topologyService.fetchTopology()
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
            try await httpClient.sendNoContent(path: "groups/\(groupID)/playback/play", method: "POST")
            message = "Grouped all rooms and resumed playback."
        }

        let updatedRooms = try await topologyService.discoverRooms()
        return SonosCommandResult(message: message, updatedRooms: annotated(updatedRooms, query: query, roomName: nil))
    }

    func pauseEverywhere() async throws -> SonosCommandResult {
        let topology = try await topologyService.fetchTopology()
        let groupIDs = Set(topology.rooms.compactMap(\.groupID))

        for groupID in groupIDs {
            try await httpClient.sendNoContent(path: "groups/\(groupID)/playback/pause", method: "POST")
        }

        let updatedRooms = try await topologyService.discoverRooms()
        return SonosCommandResult(message: "Paused playback across the selected Sonos household.", updatedRooms: updatedRooms)
    }

    private func adjustVolume(room: SonosRoom?, delta: Int, verb: String) async throws -> SonosCommandResult {
        let target = try resolveRoom(from: room)
        guard let playerID = target.playerID else {
            throw SonosControllerError.transportFailure("The selected Sonos room is missing a player identifier.")
        }

        try await httpClient.sendNoContent(
            path: "players/\(playerID)/playerVolume/relative",
            method: "POST",
            body: RelativeVolumeRequest(volumeDelta: delta)
        )

        let updatedRooms = try await topologyService.discoverRooms()
        let resolvedTarget = updatedRooms.first(where: { $0.id == target.id }) ?? target
        return SonosCommandResult(message: "\(verb) \(target.name) to \(resolvedTarget.volume).", updatedRooms: updatedRooms)
    }

    private func createGroup(householdID: String, playerIDs: [String]) async throws -> String {
        try await httpClient.sendNoContent(
            path: "households/\(householdID)/groups/createGroup",
            method: "POST",
            body: CreateGroupRequest(playerIds: playerIDs)
        )

        let response: SonosAPIGroupsResponse = try await httpClient.send(
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

        let favorites: SonosAPINamedItemsResponse = try await httpClient.send(
            path: "households/\(householdID)/favorites",
            method: "GET"
        )
        if let favorite = bestMatch(for: normalizedQuery, in: favorites.items) {
            return .favorite(id: favorite.resolvedID ?? favorite.displayName, name: favorite.displayName)
        }

        let playlists: SonosAPINamedItemsResponse = try await httpClient.send(
            path: "households/\(householdID)/playlists",
            method: "GET"
        )
        if let playlist = bestMatch(for: normalizedQuery, in: playlists.items) {
            return .playlist(id: playlist.resolvedID ?? playlist.displayName, name: playlist.displayName)
        }

        throw SonosControllerError.unsupported(
            "The real Sonos path can load Sonos favorites and playlists here, but arbitrary search queries like \"\(query)\" still need a content-service integration."
        )
    }

    private func load(_ content: ResolvedQueueContent, ontoGroupID groupID: String) async throws {
        switch content {
        case .favorite(let id, _):
            try await httpClient.sendNoContent(
                path: "groups/\(groupID)/favorites/loadFavorite",
                method: "POST",
                body: LoadFavoriteRequest(favoriteId: id, queueAction: "REPLACE")
            )

        case .playlist(let id, _):
            try await httpClient.sendNoContent(
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

        if let resolved = topologyService.lastKnownRooms.first(where: { $0.id == room.id }) {
            return resolved
        }

        return room
    }

    private func resolveHouseholdID(for room: SonosRoom) throws -> String {
        if let householdID = room.householdID {
            return householdID
        }

        if let selectedHouseholdID = topologyService.persistedSelectedHouseholdID() {
            return selectedHouseholdID
        }

        throw SonosControllerError.transportFailure("The selected Sonos room is missing a household identifier.")
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
}
