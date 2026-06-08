import Foundation

@MainActor
final class VoiceCommandCoordinator {
    private let sonosController: any SonosControlling
    private let musicPlaybackService: any MusicPlaybackServicing
    private var pendingSpotifyConnectionState: SpotifyConnectionState?

    init(
        sonosController: any SonosControlling,
        musicPlaybackService: any MusicPlaybackServicing
    ) {
        self.sonosController = sonosController
        self.musicPlaybackService = musicPlaybackService
    }

    func perform(
        _ intent: ParsedVoiceIntent,
        rooms: [SonosRoom],
        selectedRoom: SonosRoom?
    ) async throws -> SonosCommandResult {
        let resolvedRoom = resolveRoom(named: intent.targetRoom, rooms: rooms, selectedRoom: selectedRoom)

        switch intent.action {
        case .play:
            if let query = sanitizedContentQuery(intent.contentQuery) {
                return try await performSpotifyPlayback(query: query, room: resolvedRoom, scope: .singleRoom, rooms: rooms)
            }

            if intent.scope == .allRooms {
                return try await sonosController.playEverywhere(query: intent.contentQuery)
            }
            return try await sonosController.play(room: resolvedRoom, query: intent.contentQuery)

        case .pause:
            if intent.scope == .allRooms {
                return try await sonosController.pauseEverywhere()
            }
            return try await sonosController.pause(room: resolvedRoom)

        case .resume:
            if intent.scope == .allRooms {
                return try await sonosController.playEverywhere(query: nil)
            }
            return try await sonosController.resume(room: resolvedRoom)

        case .skip:
            return try await sonosController.skip(room: resolvedRoom)

        case .volumeUp:
            return try await sonosController.volumeUp(room: resolvedRoom)

        case .volumeDown:
            return try await sonosController.volumeDown(room: resolvedRoom)

        case .setVolume:
            return try await sonosController.setVolume(room: resolvedRoom, value: intent.volumeValue ?? 20)

        case .groupAll:
            if let query = sanitizedContentQuery(intent.contentQuery) {
                return try await performSpotifyPlaybackEverywhere(query: query, room: resolvedRoom)
            }

            return try await sonosController.playEverywhere(query: intent.contentQuery)
        }
    }

    func refreshSpotifyConnectionIfAuthenticationRequired(_ error: Error) async -> SpotifyConnectionState? {
        guard let spotifyError = error as? SpotifyPlaybackError,
              case .authenticationRequired = spotifyError else {
            return nil
        }

        let state = await musicPlaybackService.connectionState()
        pendingSpotifyConnectionState = state
        return state
    }

    func takePendingSpotifyConnectionState() -> SpotifyConnectionState? {
        defer {
            pendingSpotifyConnectionState = nil
        }

        return pendingSpotifyConnectionState
    }

    private func performSpotifyPlayback(
        query: String,
        room: SonosRoom?,
        scope: IntentScope,
        rooms: [SonosRoom]
    ) async throws -> SonosCommandResult {
        let result = try await musicPlaybackService.play(query: query, in: room)
        return SonosCommandResult(
            message: result.message,
            updatedRooms: annotatedRooms(
                rooms,
                result: result,
                targetRoom: room,
                scope: scope
            )
        )
    }

    private func performSpotifyPlaybackEverywhere(
        query: String,
        room: SonosRoom?
    ) async throws -> SonosCommandResult {
        let preparedPlayback = try await musicPlaybackService.preparePlayback(query: query, room: room)
        let groupedResult = try await sonosController.groupEverywhere()
        let playbackResult: MusicPlaybackResult
        do {
            playbackResult = try await musicPlaybackService.startPlayback(preparedPlayback)
        } catch {
            _ = await refreshSpotifyConnectionIfAuthenticationRequired(error)
            return SonosCommandResult(
                message: "Grouped all rooms, but Spotify playback failed: \(error.localizedDescription)",
                updatedRooms: groupedResult.updatedRooms
            )
        }

        return SonosCommandResult(
            message: "Grouped all rooms. \(playbackResult.message)",
            updatedRooms: annotatedRooms(
                groupedResult.updatedRooms,
                result: playbackResult,
                targetRoom: nil,
                scope: .allRooms
            )
        )
    }

    private func resolveRoom(named roomName: String?, rooms: [SonosRoom], selectedRoom: SonosRoom?) -> SonosRoom? {
        guard let roomName else {
            return selectedRoom
        }

        return rooms.first(where: { $0.name.caseInsensitiveCompare(roomName) == .orderedSame }) ?? selectedRoom
    }

    private func annotatedRooms(
        _ sourceRooms: [SonosRoom],
        result: MusicPlaybackResult,
        targetRoom: SonosRoom?,
        scope: IntentScope
    ) -> [SonosRoom] {
        let content = "\(result.trackTitle) - \(result.artistName)"

        return sourceRooms.map { room in
            let shouldAnnotate = scope == .allRooms || room.id == targetRoom?.id
            guard shouldAnnotate else {
                return room
            }

            var updated = room
            updated.isPlaying = true
            updated.currentContent = content
            return updated
        }
    }

    private func sanitizedContentQuery(_ query: String?) -> String? {
        guard let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
