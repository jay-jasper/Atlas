import XCTest
@testable import Atlas

final class ScreenshotTranslationConfigurationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ScreenshotTranslationConfigurationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testConfigurationReturnsNilWhenEndpointMissing() {
        let store = ScreenshotTranslationConfigurationStore(defaults: defaults)

        XCTAssertNil(store.httpConfig())
    }

    func testConfigurationReadsEndpointApiKeyAndModel() throws {
        defaults.set(" https://translation.example/api ", forKey: ScreenshotTranslationConfigurationKeys.endpoint)
        defaults.set(" secret-key ", forKey: ScreenshotTranslationConfigurationKeys.apiKey)
        defaults.set(" atlas-v1 ", forKey: ScreenshotTranslationConfigurationKeys.model)
        let store = ScreenshotTranslationConfigurationStore(defaults: defaults)

        let config = try XCTUnwrap(store.httpConfig())

        XCTAssertEqual(config.endpoint, URL(string: "https://translation.example/api"))
        XCTAssertEqual(config.apiKey, "secret-key")
        XCTAssertEqual(config.model, "atlas-v1")
    }

    func testConfigurationIgnoresInvalidEndpoint() {
        defaults.set("file:///tmp/translation", forKey: ScreenshotTranslationConfigurationKeys.endpoint)
        defaults.set(" secret-key ", forKey: ScreenshotTranslationConfigurationKeys.apiKey)
        defaults.set(" atlas-v1 ", forKey: ScreenshotTranslationConfigurationKeys.model)
        let store = ScreenshotTranslationConfigurationStore(defaults: defaults)

        XCTAssertNil(store.httpConfig())
    }

    func testConfiguredServiceUsesFallbackWithoutEndpoint() throws {
        let expected = ScreenshotTranslationResult(
            sourceText: "Hello",
            translatedText: "Bonjour",
            targetLanguage: "fr"
        )
        let service = ConfiguredScreenshotTranslationService(
            configuration: { nil },
            providerFactory: { _ in FailingTranslationProvider() },
            fallback: StubConfiguredTranslationService(result: expected)
        )

        let result = try service.translate("Hello", targetLanguage: "fr")

        XCTAssertEqual(result, expected)
    }

    func testConfiguredServiceUsesHTTPProviderWhenEndpointExists() throws {
        let expectedConfig = HTTPTranslationEndpointConfig(
            endpoint: URL(string: "https://translation.example/api")!,
            apiKey: "secret-key",
            model: "atlas-v1"
        )
        let provider = CapturingConfiguredTranslationProvider(
            result: ScreenshotTranslationResult(
                sourceText: "Hola",
                translatedText: "Hello",
                targetLanguage: "English"
            )
        )
        var capturedConfig: HTTPTranslationEndpointConfig?
        let service = ConfiguredScreenshotTranslationService(
            configuration: { expectedConfig },
            providerFactory: { config in
                capturedConfig = config
                return provider
            },
            fallback: FailingConfiguredTranslationService()
        )

        let result = try service.translate(" Hola ", targetLanguage: "English")

        XCTAssertEqual(capturedConfig, expectedConfig)
        XCTAssertEqual(provider.receivedRequest, ScreenshotTranslationRequest(sourceText: "Hola", targetLanguage: "English"))
        XCTAssertEqual(result.translatedText, "Hello")
    }

}

private struct StubConfiguredTranslationService: ScreenshotTranslating {
    let result: ScreenshotTranslationResult

    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        result
    }
}

private struct FailingConfiguredTranslationService: ScreenshotTranslating {
    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        XCTFail("Fallback should not be used when HTTP configuration exists")
        throw ScreenshotTranslationError.providerFailed("unexpected fallback")
    }
}

private struct FailingTranslationProvider: ScreenshotTranslationProviding {
    func translate(_ request: ScreenshotTranslationRequest) throws -> ScreenshotTranslationResult {
        XCTFail("Provider should not be used without HTTP configuration")
        throw ScreenshotTranslationError.providerFailed("unexpected provider")
    }
}

private final class CapturingConfiguredTranslationProvider: ScreenshotTranslationProviding {
    let result: ScreenshotTranslationResult
    private(set) var receivedRequest: ScreenshotTranslationRequest?

    init(result: ScreenshotTranslationResult) {
        self.result = result
    }

    func translate(_ request: ScreenshotTranslationRequest) throws -> ScreenshotTranslationResult {
        receivedRequest = request
        return result
    }
}
