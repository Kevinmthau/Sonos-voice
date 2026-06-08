import Foundation

struct AppConfiguration: Equatable, Sendable {
    let sonosControlBaseURL: URL
    let sonosAuthBrokerBaseURL: URL?
    let sonosCallbackURL: URL
    let spotifyClientID: String?
    let spotifyRedirectURL: URL

    static let defaultSonosControlBaseURL = URL(string: "https://api.ws.sonos.com/control/api/v1")!
    static let defaultSonosCallbackURL = URL(string: "sonosvoiceremote://auth/sonos")!
    static let defaultSpotifyRedirectURL = URL(string: "sonosvoiceremote://auth/spotify")!

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        AppConfiguration(
            sonosControlBaseURL: configuredURL("SonosControlBaseURL", bundle: bundle) ?? defaultSonosControlBaseURL,
            sonosAuthBrokerBaseURL: configuredURL("SonosAuthBrokerBaseURL", bundle: bundle),
            sonosCallbackURL: configuredURL("SonosCallbackURL", bundle: bundle) ?? defaultSonosCallbackURL,
            spotifyClientID: configuredString("SpotifyClientID", bundle: bundle),
            spotifyRedirectURL: configuredURL("SpotifyRedirectURL", bundle: bundle) ?? defaultSpotifyRedirectURL
        )
    }

    private static func configuredURL(_ key: String, bundle: Bundle) -> URL? {
        configuredString(key, bundle: bundle).flatMap(URL.init(string:))
    }

    private static func configuredString(_ key: String, bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }
}
