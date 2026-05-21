import Foundation
import Security

enum ScreenshotTranslationConfigurationKeys {
    static let endpoint = "translation.endpoint"
    static let apiKey = "translation.apiKey"
    static let model = "translation.model"
    static let targetLanguage = "translation.targetLanguage"
}

struct ScreenshotTranslationSettingsDraft: Equatable {
    var endpoint: String
    var apiKey: String
    var model: String
    var targetLanguage: String

    static let empty = ScreenshotTranslationSettingsDraft(endpoint: "", apiKey: "", model: "", targetLanguage: "")
    static let defaultTargetLanguage = "English"

    var trimmedEndpoint: String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedApiKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTargetLanguage: String {
        let t = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? Self.defaultTargetLanguage : t
    }
}

private enum AtlasKeychain {
    private static let service = "com.atlas.app"

    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        if !value.isEmpty {
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static func load(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct ScreenshotTranslationConfigurationStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func settingsDraft() -> ScreenshotTranslationSettingsDraft {
        ScreenshotTranslationSettingsDraft(
            endpoint: defaults.string(forKey: ScreenshotTranslationConfigurationKeys.endpoint) ?? "",
            apiKey: AtlasKeychain.load(account: ScreenshotTranslationConfigurationKeys.apiKey) ?? "",
            model: defaults.string(forKey: ScreenshotTranslationConfigurationKeys.model) ?? "",
            targetLanguage: defaults.string(forKey: ScreenshotTranslationConfigurationKeys.targetLanguage) ?? ""
        )
    }

    func save(_ draft: ScreenshotTranslationSettingsDraft) {
        setStringOrRemove(draft.trimmedEndpoint, forKey: ScreenshotTranslationConfigurationKeys.endpoint)
        AtlasKeychain.save(draft.trimmedApiKey, account: ScreenshotTranslationConfigurationKeys.apiKey)
        setStringOrRemove(draft.trimmedModel, forKey: ScreenshotTranslationConfigurationKeys.model)
        setStringOrRemove(draft.targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines), forKey: ScreenshotTranslationConfigurationKeys.targetLanguage)
    }

    func clear() {
        defaults.removeObject(forKey: ScreenshotTranslationConfigurationKeys.endpoint)
        AtlasKeychain.delete(account: ScreenshotTranslationConfigurationKeys.apiKey)
        defaults.removeObject(forKey: ScreenshotTranslationConfigurationKeys.model)
        defaults.removeObject(forKey: ScreenshotTranslationConfigurationKeys.targetLanguage)
    }

    func httpConfig() -> HTTPTranslationEndpointConfig? {
        guard let endpointString = defaults.string(forKey: ScreenshotTranslationConfigurationKeys.endpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !endpointString.isEmpty,
              let endpoint = URL(string: endpointString),
              let scheme = endpoint.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              let host = endpoint.host,
              isValidHost(host) else {
            return nil
        }

        return HTTPTranslationEndpointConfig(
            endpoint: endpoint,
            apiKey: cleanedOptionalString(AtlasKeychain.load(account: ScreenshotTranslationConfigurationKeys.apiKey)),
            model: cleanedOptionalString(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.model))
        )
    }

    private func isValidHost(_ host: String) -> Bool {
        let cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleaned.isEmpty
            && cleaned != "."
            && !cleaned.contains("_")
            && !cleaned.hasPrefix(".")
            && !cleaned.hasSuffix(".")
    }

    private func cleanedOptionalString(_ value: String?) -> String? {
        guard let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else {
            return nil
        }

        return cleaned
    }

    private func setStringOrRemove(_ value: String, forKey key: String) {
        if value.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }

        defaults.set(value, forKey: key)
    }
}

struct ConfiguredScreenshotTranslationService: ScreenshotTranslating {
    let configuration: () -> HTTPTranslationEndpointConfig?
    let providerFactory: (HTTPTranslationEndpointConfig) -> ScreenshotTranslationProviding
    let fallback: ScreenshotTranslating

    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        guard let config = configuration() else {
            return try fallback.translate(text, targetLanguage: targetLanguage)
        }

        let provider = providerFactory(config)
        return try ProviderBackedScreenshotTranslationService(provider: provider)
            .translate(text, targetLanguage: targetLanguage)
    }
}

enum ScreenshotTranslationServiceFactory {
    static func live(defaults: UserDefaults = .standard) -> ScreenshotTranslating {
        let store = ScreenshotTranslationConfigurationStore(defaults: defaults)
        return ConfiguredScreenshotTranslationService(
            configuration: store.httpConfig,
            providerFactory: { config in
                ScreenshotHTTPTranslationProvider(config: config)
            },
            fallback: LocalPlaceholderScreenshotTranslationService()
        )
    }
}
