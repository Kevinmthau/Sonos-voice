import Foundation

protocol OpenAIAPIKeyStoring: Sendable {
    func loadAPIKey() -> String?
    func saveAPIKey(_ apiKey: String)
    func deleteAPIKey()
}

struct OpenAIAPIKeyStore: OpenAIAPIKeyStoring {
    private let store: KeychainCredentialStore
    private let account = "api-key"

    init(store: KeychainCredentialStore = KeychainCredentialStore(service: "com.kevinthau.SonosVoiceRemote.openai")) {
        self.store = store
    }

    func loadAPIKey() -> String? {
        let value = store.loadString(account: account)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    func saveAPIKey(_ apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteAPIKey()
        } else {
            store.saveString(trimmed, account: account)
        }
    }

    func deleteAPIKey() {
        store.delete(account: account)
    }
}
