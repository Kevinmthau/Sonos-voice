import Foundation

enum SonosAction: String, CaseIterable, Codable {
    case play
    case pause
    case resume
    case skip
    case volumeUp = "volume_up"
    case volumeDown = "volume_down"
    case setVolume = "set_volume"
    case groupAll = "group_all"

    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ")
    }
}

enum IntentScope: String, Codable {
    case singleRoom = "single_room"
    case allRooms = "all_rooms"

    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ")
    }
}

struct ParsedVoiceIntent: Equatable, Codable {
    let originalTranscript: String
    let action: SonosAction
    let targetRoom: String?
    let contentQuery: String?
    let volumeValue: Int?
    let scope: IntentScope

    var summary: String {
        var fragments = [
            "action: \(action.displayName)",
            "scope: \(scope.displayName)"
        ]

        if let targetRoom, !targetRoom.isEmpty {
            fragments.append("room: \(targetRoom)")
        }

        if let contentQuery, !contentQuery.isEmpty {
            fragments.append("query: \(contentQuery)")
        }

        if let volumeValue {
            fragments.append("volume: \(volumeValue)")
        }

        return fragments.joined(separator: " | ")
    }
}
