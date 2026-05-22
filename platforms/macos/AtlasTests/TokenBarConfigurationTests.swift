import XCTest
@testable import Atlas

final class TokenBarConfigurationTests: XCTestCase {
    func testSaveLoadAndClearConfigurationWithoutExposingKeyInDefaults() {
        let defaults = UserDefaults(suiteName: "TokenBarConfigurationTests.save")!
        defaults.removePersistentDomain(forName: "TokenBarConfigurationTests.save")
        let keychain = InMemoryTokenBarSecretStore()
        let store = TokenBarConfigurationStore(defaults: defaults, secretStore: keychain)

        store.save(TokenBarProviderConfiguration(
            provider: .openAI,
            displayName: "Work",
            endpoint: URL(string: "https://api.openai.com")!,
            apiKey: "sk-test",
            defaultModel: "gpt-4.1-mini"
        ))

        let loaded = store.load()
        XCTAssertEqual(loaded, TokenBarProviderConfiguration(
            provider: .openAI,
            displayName: "Work",
            endpoint: URL(string: "https://api.openai.com")!,
            apiKey: "sk-test",
            defaultModel: "gpt-4.1-mini"
        ))
        XCTAssertNil(defaults.string(forKey: TokenBarConfigurationKeys.apiKey))
        XCTAssertEqual(keychain.load(account: TokenBarConfigurationKeys.apiKey), "sk-test")

        store.clear()
        XCTAssertNil(store.load())
        XCTAssertNil(keychain.load(account: TokenBarConfigurationKeys.apiKey))
    }
}
