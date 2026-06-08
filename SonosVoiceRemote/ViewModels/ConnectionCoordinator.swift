import Foundation

@MainActor
final class ConnectionCoordinator {
    private let sonosController: any SonosControlling
    private let musicPlaybackService: any MusicPlaybackServicing
    private let openAIAPIKeyStore: any OpenAIAPIKeyStoring

    init(
        sonosController: any SonosControlling,
        musicPlaybackService: any MusicPlaybackServicing,
        openAIAPIKeyStore: any OpenAIAPIKeyStoring
    ) {
        self.sonosController = sonosController
        self.musicPlaybackService = musicPlaybackService
        self.openAIAPIKeyStore = openAIAPIKeyStore
    }

    func sonosConnectionState() async -> SonosConnectionState {
        await sonosController.connectionState()
    }

    func connectSonos() async throws -> SonosConnectionState {
        try await sonosController.connect()
    }

    func disconnectSonos() async -> SonosConnectionState {
        await sonosController.disconnect()
    }

    func selectHousehold(id: String) async throws -> SonosConnectionState {
        try await sonosController.selectHousehold(id: id)
    }

    func discoverRooms() async throws -> [SonosRoom] {
        try await sonosController.discoverRooms()
    }

    func handleSonosCallback(_ url: URL) async throws -> SonosConnectionState {
        try await sonosController.handleAuthorizationCallback(url)
    }

    func spotifyConnectionState() async -> SpotifyConnectionState {
        await musicPlaybackService.connectionState()
    }

    func connectSpotify() async throws -> SpotifyConnectionState {
        try await musicPlaybackService.connect()
    }

    func disconnectSpotify() async -> SpotifyConnectionState {
        await musicPlaybackService.disconnect()
    }

    func handleSpotifyCallback(_ url: URL) async throws -> SpotifyConnectionState {
        try await musicPlaybackService.handleAuthorizationCallback(url)
    }

    func canHandleSpotifyCallback(_ url: URL) -> Bool {
        musicPlaybackService.canHandleAuthorizationCallback(url)
    }

    func hasOpenAIAPIKey() -> Bool {
        openAIAPIKeyStore.loadAPIKey() != nil
    }

    func saveOpenAIAPIKey(_ apiKey: String) {
        openAIAPIKeyStore.saveAPIKey(apiKey)
    }

    func clearOpenAIAPIKey() {
        openAIAPIKeyStore.deleteAPIKey()
    }
}
