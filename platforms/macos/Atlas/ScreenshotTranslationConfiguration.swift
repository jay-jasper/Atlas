import Foundation

enum ScreenshotTranslationConfigurationKeys {
    static let endpoint = "translation.endpoint"
    static let apiKey = "translation.apiKey"
    static let model = "translation.model"
}

struct ScreenshotTranslationSettingsDraft: Equatable {
    var endpoint: String
    var apiKey: String
    var model: String

    static let empty = ScreenshotTranslationSettingsDraft(endpoint: "", apiKey: "", model: "")

    var trimmedEndpoint: String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedApiKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
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
            apiKey: defaults.string(forKey: ScreenshotTranslationConfigurationKeys.apiKey) ?? "",
            model: defaults.string(forKey: ScreenshotTranslationConfigurationKeys.model) ?? ""
        )
    }

    func save(_ draft: ScreenshotTranslationSettingsDraft) {
        setStringOrRemove(draft.trimmedEndpoint, forKey: ScreenshotTranslationConfigurationKeys.endpoint)
        setStringOrRemove(draft.trimmedApiKey, forKey: ScreenshotTranslationConfigurationKeys.apiKey)
        setStringOrRemove(draft.trimmedModel, forKey: ScreenshotTranslationConfigurationKeys.model)
    }

    func clear() {
        defaults.removeObject(forKey: ScreenshotTranslationConfigurationKeys.endpoint)
        defaults.removeObject(forKey: ScreenshotTranslationConfigurationKeys.apiKey)
        defaults.removeObject(forKey: ScreenshotTranslationConfigurationKeys.model)
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
            apiKey: cleanedOptionalString(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.apiKey)),
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
