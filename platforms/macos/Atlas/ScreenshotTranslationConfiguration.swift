import Foundation

enum ScreenshotTranslationConfigurationKeys {
    static let endpoint = "translation.endpoint"
    static let apiKey = "translation.apiKey"
    static let model = "translation.model"
}

struct ScreenshotTranslationConfigurationStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func httpConfig() -> HTTPTranslationEndpointConfig? {
        guard let endpointString = defaults.string(forKey: ScreenshotTranslationConfigurationKeys.endpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !endpointString.isEmpty,
              let endpoint = URL(string: endpointString),
              let scheme = endpoint.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              endpoint.host != nil else {
            return nil
        }

        return HTTPTranslationEndpointConfig(
            endpoint: endpoint,
            apiKey: cleanedOptionalString(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.apiKey)),
            model: cleanedOptionalString(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.model))
        )
    }

    private func cleanedOptionalString(_ value: String?) -> String? {
        guard let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else {
            return nil
        }

        return cleaned
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
