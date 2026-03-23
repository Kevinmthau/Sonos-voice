import Foundation

struct SonosGroup: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let roomNames: [String]
}

struct SonosHousehold: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let roomNames: [String]

    var summary: String {
        if roomNames.isEmpty {
            return name
        }

        return "\(name): \(roomNames.joined(separator: ", "))"
    }
}

enum SonosConnectionStatus: String, Codable, Sendable {
    case ready
    case authenticationRequired
    case configurationRequired
    case unavailable
}

struct SonosConnectionState: Equatable, Codable, Sendable {
    let status: SonosConnectionStatus
    let detail: String
    let households: [SonosHousehold]
    let selectedHouseholdID: String?
    let authorizationURL: URL?

    var isReady: Bool {
        status == .ready
    }

    var selectedHousehold: SonosHousehold? {
        households.first(where: { $0.id == selectedHouseholdID })
    }

    var selectedHouseholdName: String {
        selectedHousehold?.name ?? "No household selected"
    }

    static func configurationRequired(_ detail: String) -> SonosConnectionState {
        SonosConnectionState(
            status: .configurationRequired,
            detail: detail,
            households: [],
            selectedHouseholdID: nil,
            authorizationURL: nil
        )
    }

    static func authenticationRequired(_ detail: String, authorizationURL: URL? = nil) -> SonosConnectionState {
        SonosConnectionState(
            status: .authenticationRequired,
            detail: detail,
            households: [],
            selectedHouseholdID: nil,
            authorizationURL: authorizationURL
        )
    }

    static func unavailable(
        _ detail: String,
        households: [SonosHousehold] = [],
        selectedHouseholdID: String? = nil,
        authorizationURL: URL? = nil
    ) -> SonosConnectionState {
        SonosConnectionState(
            status: .unavailable,
            detail: detail,
            households: households,
            selectedHouseholdID: selectedHouseholdID,
            authorizationURL: authorizationURL
        )
    }

    static func ready(
        detail: String,
        households: [SonosHousehold],
        selectedHouseholdID: String?
    ) -> SonosConnectionState {
        SonosConnectionState(
            status: .ready,
            detail: detail,
            households: households,
            selectedHouseholdID: selectedHouseholdID,
            authorizationURL: nil
        )
    }
}
