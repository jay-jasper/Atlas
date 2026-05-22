import Foundation
import Security

enum TokenBarConfigurationKeys {
    static let provider = "tokenbar.provider"
    static let displayName = "tokenbar.displayName"
    static let endpoint = "tokenbar.endpoint"
    static let apiKey = "tokenbar.apiKey"
    static let defaultModel = "tokenbar.defaultModel"
}

protocol TokenBarSecretStoring {
    func save(_ value: String, account: String)
    func load(account: String) -> String?
    func delete(account: String)
}

struct TokenBarKeychainSecretStore: TokenBarSecretStoring {
    private let service = "com.atlas.app.tokenbar"

    func save(_ value: String, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var addQuery = query
        addQuery[kSecValueData] = Data(trimmed.utf8)
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func load(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class InMemoryTokenBarSecretStore: TokenBarSecretStoring {
    private var values: [String: String] = [:]

    func save(_ value: String, account: String) {
        values[account] = value
    }

    func load(account: String) -> String? {
        values[account]
    }

    func delete(account: String) {
        values.removeValue(forKey: account)
    }
}

struct TokenBarConfigurationStore {
    let defaults: UserDefaults
    let secretStore: TokenBarSecretStoring

    init(
        defaults: UserDefaults = .standard,
        secretStore: TokenBarSecretStoring = TokenBarKeychainSecretStore()
    ) {
        self.defaults = defaults
        self.secretStore = secretStore
    }

    func save(_ config: TokenBarProviderConfiguration) {
        defaults.set(config.provider.rawValue, forKey: TokenBarConfigurationKeys.provider)
        defaults.set(config.displayName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: TokenBarConfigurationKeys.displayName)
        defaults.set(config.endpoint.absoluteString, forKey: TokenBarConfigurationKeys.endpoint)
        defaults.set(config.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines), forKey: TokenBarConfigurationKeys.defaultModel)
        defaults.removeObject(forKey: TokenBarConfigurationKeys.apiKey)
        secretStore.save(config.apiKey, account: TokenBarConfigurationKeys.apiKey)
    }

    func load() -> TokenBarProviderConfiguration? {
        guard let providerRaw = defaults.string(forKey: TokenBarConfigurationKeys.provider),
              let provider = TokenBarProvider(rawValue: providerRaw),
              let endpointRaw = defaults.string(forKey: TokenBarConfigurationKeys.endpoint),
              let endpoint = URL(string: endpointRaw),
              let apiKey = secretStore.load(account: TokenBarConfigurationKeys.apiKey)
        else {
            return nil
        }

        return TokenBarProviderConfiguration(
            provider: provider,
            displayName: defaults.string(forKey: TokenBarConfigurationKeys.displayName) ?? provider.title,
            endpoint: endpoint,
            apiKey: apiKey,
            defaultModel: defaults.string(forKey: TokenBarConfigurationKeys.defaultModel) ?? ""
        )
    }

    func clear() {
        defaults.removeObject(forKey: TokenBarConfigurationKeys.provider)
        defaults.removeObject(forKey: TokenBarConfigurationKeys.displayName)
        defaults.removeObject(forKey: TokenBarConfigurationKeys.endpoint)
        defaults.removeObject(forKey: TokenBarConfigurationKeys.apiKey)
        defaults.removeObject(forKey: TokenBarConfigurationKeys.defaultModel)
        secretStore.delete(account: TokenBarConfigurationKeys.apiKey)
    }
}
