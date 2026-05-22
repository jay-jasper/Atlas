import XCTest
@testable import Atlas

final class TokenBarSettingsViewTests: XCTestCase {
    func testSettingsSaveStoresSecretOnlyInInjectedKeyStore() throws {
        let defaults = UserDefaults(suiteName: "TokenBarSettingsViewTests.save")!
        defaults.removePersistentDomain(forName: "TokenBarSettingsViewTests.save")
        let keyStore = InMemoryTokenBarSecretStore()
        let store = TokenBarConfigurationStore(defaults: defaults, secretStore: keyStore)

        let save: (TokenBarProviderConfiguration) -> Void = { store.save($0) }
        let clear: () -> Void = { store.clear() }
        let panel = TokenBarSettingsPanel(configuration: nil, onSave: save, onClear: clear)
        _ = panel

        save(TokenBarProviderConfiguration(
            provider: .openAI,
            displayName: "Work",
            endpoint: URL(string: "https://api.openai.com")!,
            apiKey: "sk-test",
            defaultModel: "gpt-4.1-mini"
        ))

        XCTAssertNil(defaults.string(forKey: TokenBarConfigurationKeys.apiKey))
        XCTAssertEqual(keyStore.load(account: TokenBarConfigurationKeys.apiKey), "sk-test")
        XCTAssertEqual(store.load()?.displayName, "Work")
        clear()
    }

    func testSettingsClearRemovesConfigurationAndInjectedSecret() throws {
        let defaults = UserDefaults(suiteName: "TokenBarSettingsViewTests.clear")!
        defaults.removePersistentDomain(forName: "TokenBarSettingsViewTests.clear")
        let keyStore = InMemoryTokenBarSecretStore()
        let store = TokenBarConfigurationStore(defaults: defaults, secretStore: keyStore)

        let save: (TokenBarProviderConfiguration) -> Void = { store.save($0) }
        let clear: () -> Void = { store.clear() }
        let panel = TokenBarSettingsPanel(configuration: nil, onSave: save, onClear: clear)
        _ = panel

        save(TokenBarProviderConfiguration(
            provider: .openAI,
            displayName: "Work",
            endpoint: URL(string: "https://api.openai.com")!,
            apiKey: "sk-test",
            defaultModel: "gpt-4.1-mini"
        ))
        clear()

        XCTAssertNil(store.load())
        XCTAssertNil(keyStore.load(account: TokenBarConfigurationKeys.apiKey))
    }
}
