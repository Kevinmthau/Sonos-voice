import Foundation

struct SonosRoom: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let playerID: String?
    let groupID: String?
    let householdID: String?
    var volume: Int
    var isCoordinator: Bool
    var groupName: String?
    var isPlaying: Bool
    var currentContent: String?

    init(
        id: String? = nil,
        name: String,
        playerID: String? = nil,
        groupID: String? = nil,
        householdID: String? = nil,
        volume: Int = 20,
        isCoordinator: Bool = false,
        groupName: String? = nil,
        isPlaying: Bool = false,
        currentContent: String? = nil
    ) {
        self.id = id ?? playerID ?? SonosRoom.makeIdentifier(from: name)
        self.name = name
        self.playerID = playerID
        self.groupID = groupID
        self.householdID = householdID
        self.volume = max(0, min(100, volume))
        self.isCoordinator = isCoordinator
        self.groupName = groupName
        self.isPlaying = isPlaying
        self.currentContent = currentContent
    }

    private static func makeIdentifier(from name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
