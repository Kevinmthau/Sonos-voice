import Foundation

struct SonosCommandResult: Equatable, Sendable {
    let message: String
    let updatedRooms: [SonosRoom]
}

enum SonosControllerError: LocalizedError, Sendable {
    case noRoomSelected
    case roomNotFound(String)
    case householdNotFound(String)
    case notConfigured(String)
    case authenticationRequired(String)
    case unsupported(String)
    case transportFailure(String)

    var errorDescription: String? {
        switch self {
        case .noRoomSelected:
            return "Select a Sonos room before sending a room-specific command."
        case .roomNotFound(let roomName):
            return "Could not find the room named \(roomName)."
        case .householdNotFound(let householdID):
            return "Could not find the Sonos household \(householdID)."
        case .notConfigured(let message):
            return message
        case .authenticationRequired(let message):
            return message
        case .unsupported(let message):
            return message
        case .transportFailure(let message):
            return message
        }
    }
}

protocol SonosControlling {
    func connectionState() async -> SonosConnectionState
    func connect() async throws -> SonosConnectionState
    func disconnect() async -> SonosConnectionState
    func selectHousehold(id: String) async throws -> SonosConnectionState
    func authorizationURL() async -> URL?
    func handleAuthorizationCallback(_ url: URL) async throws -> SonosConnectionState
    func discoverRooms() async throws -> [SonosRoom]
    func play(room: SonosRoom?, query: String?) async throws -> SonosCommandResult
    func pause(room: SonosRoom?) async throws -> SonosCommandResult
    func resume(room: SonosRoom?) async throws -> SonosCommandResult
    func skip(room: SonosRoom?) async throws -> SonosCommandResult
    func setVolume(room: SonosRoom?, value: Int) async throws -> SonosCommandResult
    func volumeUp(room: SonosRoom?) async throws -> SonosCommandResult
    func volumeDown(room: SonosRoom?) async throws -> SonosCommandResult
    func playEverywhere(query: String?) async throws -> SonosCommandResult
    func pauseEverywhere() async throws -> SonosCommandResult
}
