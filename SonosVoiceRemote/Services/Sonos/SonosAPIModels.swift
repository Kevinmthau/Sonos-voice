import Foundation

struct StoredAuthTokens: Codable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Date?
}

struct SonosAPIHouseholdsResponse: Decodable {
    let households: [SonosAPIHousehold]
}

struct SonosAPIHousehold: Decodable {
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

struct SonosAPIGroupsResponse: Decodable {
    let players: [SonosAPIPlayer]
    let groups: [SonosAPIGroup]
}

struct SonosAPIPlayer: Decodable {
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

struct SonosAPIGroup: Decodable {
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

struct SonosAPIPlayerVolumeResponse: Decodable {
    let volume: Int?
}

struct SonosAPINamedItemsResponse: Decodable {
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

struct SonosAPINamedItem: Decodable {
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

struct SonosAPIErrorResponse: Decodable {
    let message: String?
    let error: String?
    let reason: String?

    var detail: String? {
        message ?? error ?? reason
    }
}

struct CreateGroupRequest: Encodable {
    let playerIds: [String]
}

struct SetVolumeRequest: Encodable {
    let volume: Int
}

struct RelativeVolumeRequest: Encodable {
    let volumeDelta: Int
}

struct LoadFavoriteRequest: Encodable {
    let favoriteId: String
    let queueAction: String
}

struct LoadPlaylistRequest: Encodable {
    let playlistId: String
    let queueAction: String
}

struct SonosEmptyResponse: Decodable { }

struct SonosTopology {
    let household: SonosHousehold
    let rooms: [SonosRoom]
}

enum ResolvedQueueContent {
    case favorite(id: String, name: String)
    case playlist(id: String, name: String)

    var displayName: String {
        switch self {
        case .favorite(_, let name), .playlist(_, let name):
            return name
        }
    }
}

struct SonosOAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
