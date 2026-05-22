# Translation Engine v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the screenshot translation placeholder-only path with a configurable, testable Translation Engine v1 that can call an Atlas-compatible HTTP translation endpoint.

**Architecture:** Keep the existing `ScreenshotTranslating` API as the UI-facing boundary so `ContentView` and `ScreenshotEditorView` stay stable. Add a provider layer underneath it: one provider-backed service for validation/delegation, one HTTP provider with injectable transport for deterministic tests, and one configuration service that chooses HTTP only when a valid endpoint is configured. The default app behavior remains safe: without configuration, translation still reports unsupported rather than pretending to translate.

**Tech Stack:** Swift, Foundation `URLRequest` / `URLSession`, XCTest, existing SwiftUI screenshot translation UI.

---

## Scope Check

This plan covers Translation Engine v1 only:

- Add a provider abstraction under `ScreenshotTranslating`.
- Add a deterministic Atlas-compatible HTTP provider.
- Add a configuration-backed live service that uses `UserDefaults` for endpoint/API key/model.
- Preserve the existing UI call path: `ContentView -> AtlasBridge.translateScreenshotText -> ScreenshotTranslating`.
- Keep tests deterministic through injected providers/transports.

This plan does not implement a settings UI, Keychain storage, OpenAI/DeepL/Ollama-specific adapters, streaming translation, multi-engine comparison, language auto-detection UI, billing, or cloud OCR.

## File Structure

- Modify: `platforms/macos/Atlas/ScreenshotTranslationService.swift`
  - Keep existing `ScreenshotTranslationResult`, `ScreenshotTranslating`, `ScreenshotTranslationError`, and `LocalPlaceholderScreenshotTranslationService`.
  - Add `ScreenshotTranslationRequest`, `ScreenshotTranslationProviding`, and `ProviderBackedScreenshotTranslationService`.
  - Add new error cases for HTTP/configuration failures.
- Create: `platforms/macos/Atlas/ScreenshotHTTPTranslationProvider.swift`
  - Builds and sends Atlas-compatible HTTP translation requests.
  - Parses `translated_text` JSON responses.
  - Uses injectable `HTTPTranslationTransport`.
- Create: `platforms/macos/Atlas/ScreenshotTranslationConfiguration.swift`
  - Reads translation endpoint, API key, and model from `UserDefaults`.
  - Builds the app's live `ScreenshotTranslating` service.
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
  - Replace direct placeholder default with configuration-backed live service.
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Add new Swift source files to the Atlas app target.
- Modify: `platforms/macos/AtlasTests/ScreenshotTranslationServiceTests.swift`
  - Add provider-backed service tests.
- Create: `platforms/macos/AtlasTests/ScreenshotHTTPTranslationProviderTests.swift`
  - Test HTTP request construction, response parsing, status errors, and transport errors.
- Create: `platforms/macos/AtlasTests/ScreenshotTranslationConfigurationTests.swift`
  - Test UserDefaults-backed live service selection without network calls.
- Modify: `docs/superpowers/plans/2026-05-20-translation-engine-v1.md`
  - Record final verification notes after implementation.

---

### Task 1: Provider-Backed Translation Service

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotTranslationService.swift`
- Modify: `platforms/macos/AtlasTests/ScreenshotTranslationServiceTests.swift`

- [x] **Step 1: Add failing provider-backed service tests**

Append these tests and helper to `platforms/macos/AtlasTests/ScreenshotTranslationServiceTests.swift`:

```swift
func testProviderBackedServiceDelegatesTrimmedRequestToProvider() throws {
    let provider = CapturingScreenshotTranslationProvider(
        result: ScreenshotTranslationResult(
            sourceText: "Hola",
            translatedText: "Hello",
            targetLanguage: "English"
        )
    )
    let service = ProviderBackedScreenshotTranslationService(provider: provider)

    let result = try service.translate("  Hola\n", targetLanguage: "English")

    XCTAssertEqual(provider.receivedRequest, ScreenshotTranslationRequest(sourceText: "Hola", targetLanguage: "English"))
    XCTAssertEqual(result.translatedText, "Hello")
}

func testProviderBackedServiceRejectsBlankTextBeforeProviderCall() {
    let provider = CapturingScreenshotTranslationProvider(
        result: ScreenshotTranslationResult(sourceText: "", translatedText: "", targetLanguage: "English")
    )
    let service = ProviderBackedScreenshotTranslationService(provider: provider)

    XCTAssertThrowsError(try service.translate(" \n ", targetLanguage: "English")) { error in
        XCTAssertEqual(error.localizedDescription, "Screenshot text is empty and cannot be translated")
    }
    XCTAssertNil(provider.receivedRequest)
}

func testProviderErrorMessageIsExposed() {
    XCTAssertEqual(
        ScreenshotTranslationError.providerFailed("network unavailable").localizedDescription,
        "Screenshot translation failed: network unavailable"
    )
}

private final class CapturingScreenshotTranslationProvider: ScreenshotTranslationProviding {
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
```

- [x] **Step 2: Run service tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationServiceTests
```

Expected: FAIL with missing types such as `ProviderBackedScreenshotTranslationService`, `ScreenshotTranslationRequest`, `ScreenshotTranslationProviding`, and `ScreenshotTranslationError.providerFailed`.

- [x] **Step 3: Extend the translation service boundary**

Update `platforms/macos/Atlas/ScreenshotTranslationService.swift` to this content:

```swift
import Foundation

struct ScreenshotTranslationResult: Equatable {
    let sourceText: String
    let translatedText: String
    let targetLanguage: String
}

struct ScreenshotTranslationRequest: Equatable {
    let sourceText: String
    let targetLanguage: String
}

protocol ScreenshotTranslationProviding {
    func translate(_ request: ScreenshotTranslationRequest) throws -> ScreenshotTranslationResult
}

protocol ScreenshotTranslating {
    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult
}

enum ScreenshotTranslationError: LocalizedError, Equatable {
    case emptyText
    case unsupportedLocalTranslation
    case missingEndpoint
    case invalidResponse
    case httpStatus(Int)
    case providerFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Screenshot text is empty and cannot be translated"
        case .unsupportedLocalTranslation:
            return "Local screenshot translation is not supported yet"
        case .missingEndpoint:
            return "Screenshot translation endpoint is not configured"
        case .invalidResponse:
            return "Screenshot translation response could not be decoded"
        case .httpStatus(let statusCode):
            return "Screenshot translation request failed with HTTP \(statusCode)"
        case .providerFailed(let message):
            return "Screenshot translation failed: \(message)"
        }
    }
}

struct LocalPlaceholderScreenshotTranslationService: ScreenshotTranslating {
    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScreenshotTranslationError.emptyText
        }

        throw ScreenshotTranslationError.unsupportedLocalTranslation
    }
}

struct ProviderBackedScreenshotTranslationService: ScreenshotTranslating {
    let provider: ScreenshotTranslationProviding

    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ScreenshotTranslationError.emptyText
        }

        return try provider.translate(
            ScreenshotTranslationRequest(
                sourceText: trimmedText,
                targetLanguage: targetLanguage
            )
        )
    }
}
```

- [x] **Step 4: Run service tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationServiceTests
```

Expected: PASS, all `ScreenshotTranslationServiceTests` pass.

- [x] **Step 5: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotTranslationService.swift \
  platforms/macos/AtlasTests/ScreenshotTranslationServiceTests.swift
git commit -m "feat(macos): add translation provider service"
```

---

### Task 2: Atlas-Compatible HTTP Translation Provider

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotHTTPTranslationProvider.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotHTTPTranslationProviderTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Add failing HTTP provider tests**

Create `platforms/macos/AtlasTests/ScreenshotHTTPTranslationProviderTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScreenshotHTTPTranslationProviderTests: XCTestCase {
    func testBuildsPostRequestWithJsonBodyAndAuthorizationHeader() throws {
        let transport = StubHTTPTranslationTransport(
            response: .success(Self.response(
                statusCode: 200,
                body: #"{"translated_text":"Hello"}"#
            ))
        )
        let provider = ScreenshotHTTPTranslationProvider(
            config: HTTPTranslationEndpointConfig(
                endpoint: URL(string: "https://example.com/translate")!,
                apiKey: "secret",
                model: "atlas-test"
            ),
            transport: transport
        )

        let result = try provider.translate(
            ScreenshotTranslationRequest(sourceText: "Hola", targetLanguage: "English")
        )

        XCTAssertEqual(result, ScreenshotTranslationResult(sourceText: "Hola", translatedText: "Hello", targetLanguage: "English"))
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest?.url?.absoluteString, "https://example.com/translate")
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")

        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["text"] as? String, "Hola")
        XCTAssertEqual(json?["target_language"] as? String, "English")
        XCTAssertEqual(json?["model"] as? String, "atlas-test")
    }

    func testOmitsAuthorizationAndModelWhenNotConfigured() throws {
        let transport = StubHTTPTranslationTransport(
            response: .success(Self.response(
                statusCode: 200,
                body: #"{"translated_text":"Bonjour"}"#
            ))
        )
        let provider = ScreenshotHTTPTranslationProvider(
            config: HTTPTranslationEndpointConfig(
                endpoint: URL(string: "https://example.com/translate")!,
                apiKey: nil,
                model: nil
            ),
            transport: transport
        )

        _ = try provider.translate(
            ScreenshotTranslationRequest(sourceText: "Hello", targetLanguage: "French")
        )

        XCTAssertNil(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertNil(json?["model"])
    }

    func testThrowsForNonSuccessHTTPStatus() {
        let transport = StubHTTPTranslationTransport(
            response: .success(Self.response(statusCode: 503, body: #"{"error":"down"}"#))
        )
        let provider = ScreenshotHTTPTranslationProvider(
            config: HTTPTranslationEndpointConfig(endpoint: URL(string: "https://example.com/translate")!),
            transport: transport
        )

        XCTAssertThrowsError(
            try provider.translate(ScreenshotTranslationRequest(sourceText: "Hola", targetLanguage: "English"))
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Screenshot translation request failed with HTTP 503")
        }
    }

    func testThrowsForMissingTranslatedText() {
        let transport = StubHTTPTranslationTransport(
            response: .success(Self.response(statusCode: 200, body: #"{"message":"ok"}"#))
        )
        let provider = ScreenshotHTTPTranslationProvider(
            config: HTTPTranslationEndpointConfig(endpoint: URL(string: "https://example.com/translate")!),
            transport: transport
        )

        XCTAssertThrowsError(
            try provider.translate(ScreenshotTranslationRequest(sourceText: "Hola", targetLanguage: "English"))
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Screenshot translation response could not be decoded")
        }
    }

    func testWrapsTransportFailure() {
        let transport = StubHTTPTranslationTransport(
            response: .failure(StubTransportError.offline)
        )
        let provider = ScreenshotHTTPTranslationProvider(
            config: HTTPTranslationEndpointConfig(endpoint: URL(string: "https://example.com/translate")!),
            transport: transport
        )

        XCTAssertThrowsError(
            try provider.translate(ScreenshotTranslationRequest(sourceText: "Hola", targetLanguage: "English"))
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Screenshot translation failed: offline")
        }
    }

    private static func response(statusCode: Int, body: String) -> (Data, HTTPURLResponse) {
        (
            Data(body.utf8),
            HTTPURLResponse(
                url: URL(string: "https://example.com/translate")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private final class StubHTTPTranslationTransport: HTTPTranslationTransporting {
    let response: Result<(Data, HTTPURLResponse), Error>
    private(set) var lastRequest: URLRequest?

    init(response: Result<(Data, HTTPURLResponse), Error>) {
        self.response = response
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        return try response.get()
    }
}

private enum StubTransportError: LocalizedError {
    case offline

    var errorDescription: String? {
        "offline"
    }
}
```

- [x] **Step 2: Add test file to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `ScreenshotHTTPTranslationProviderTests.swift` is listed in:

```text
PBXFileReference
PBXBuildFile
AtlasTests group
AtlasTests Sources build phase
```

- [x] **Step 3: Run HTTP provider tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotHTTPTranslationProviderTests
```

Expected: FAIL with missing `ScreenshotHTTPTranslationProvider`, `HTTPTranslationEndpointConfig`, and `HTTPTranslationTransporting`.

- [x] **Step 4: Add HTTP provider implementation**

Create `platforms/macos/Atlas/ScreenshotHTTPTranslationProvider.swift`:

```swift
import Foundation

struct HTTPTranslationEndpointConfig: Equatable {
    let endpoint: URL
    let apiKey: String?
    let model: String?

    init(endpoint: URL, apiKey: String? = nil, model: String? = nil) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
    }
}

protocol HTTPTranslationTransporting {
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPTranslationTransport: HTTPTranslationTransporting {
    let session: URLSession
    let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 30) {
        self.session = session
        self.timeout = timeout
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var output: Result<(Data, HTTPURLResponse), Error>!

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                output = .failure(error)
                return
            }

            guard let data, let httpResponse = response as? HTTPURLResponse else {
                output = .failure(ScreenshotTranslationError.invalidResponse)
                return
            }

            output = .success((data, httpResponse))
        }

        task.resume()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            throw ScreenshotTranslationError.providerFailed("request timed out")
        }

        return try output.get()
    }
}

struct ScreenshotHTTPTranslationProvider: ScreenshotTranslationProviding {
    let config: HTTPTranslationEndpointConfig
    let transport: HTTPTranslationTransporting

    init(
        config: HTTPTranslationEndpointConfig,
        transport: HTTPTranslationTransporting = URLSessionHTTPTranslationTransport()
    ) {
        self.config = config
        self.transport = transport
    }

    func translate(_ request: ScreenshotTranslationRequest) throws -> ScreenshotTranslationResult {
        var urlRequest = URLRequest(url: config.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = config.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: String] = [
            "text": request.sourceText,
            "target_language": request.targetLanguage
        ]

        if let model = config.model, !model.isEmpty {
            body["model"] = model
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: HTTPURLResponse

        do {
            (data, response) = try transport.send(urlRequest)
        } catch let error as ScreenshotTranslationError {
            throw error
        } catch {
            throw ScreenshotTranslationError.providerFailed(error.localizedDescription)
        }

        guard (200...299).contains(response.statusCode) else {
            throw ScreenshotTranslationError.httpStatus(response.statusCode)
        }

        let decoded = try JSONDecoder().decode(HTTPTranslationResponse.self, from: data)
        guard !decoded.translatedText.isEmpty else {
            throw ScreenshotTranslationError.invalidResponse
        }

        return ScreenshotTranslationResult(
            sourceText: request.sourceText,
            translatedText: decoded.translatedText,
            targetLanguage: request.targetLanguage
        )
    }
}

private struct HTTPTranslationResponse: Decodable {
    let translatedText: String

    enum CodingKeys: String, CodingKey {
        case translatedText = "translated_text"
    }
}
```

- [x] **Step 5: Add app source file to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `ScreenshotHTTPTranslationProvider.swift` is listed in:

```text
PBXFileReference
PBXBuildFile
Atlas group
Atlas Sources build phase
```

- [x] **Step 6: Run HTTP provider tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotHTTPTranslationProviderTests
```

Expected: PASS, 5 tests.

- [x] **Step 7: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotHTTPTranslationProvider.swift \
  platforms/macos/AtlasTests/ScreenshotHTTPTranslationProviderTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add http screenshot translation provider"
```

---

### Task 3: Configuration-Backed Live Translation Service

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotTranslationConfiguration.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotTranslationConfigurationTests.swift`
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Add failing configuration tests**

Create `platforms/macos/AtlasTests/ScreenshotTranslationConfigurationTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScreenshotTranslationConfigurationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AtlasTranslationConfigurationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        AtlasBridge.translationService = ScreenshotTranslationServiceFactory.live()
        super.tearDown()
    }

    func testConfigurationReturnsNilWhenEndpointMissing() {
        let store = ScreenshotTranslationConfigurationStore(defaults: defaults)

        XCTAssertNil(store.httpConfig())
    }

    func testConfigurationReadsEndpointApiKeyAndModel() {
        defaults.set("https://example.com/translate", forKey: ScreenshotTranslationConfigurationKeys.endpoint)
        defaults.set("secret", forKey: ScreenshotTranslationConfigurationKeys.apiKey)
        defaults.set("atlas-test", forKey: ScreenshotTranslationConfigurationKeys.model)

        let store = ScreenshotTranslationConfigurationStore(defaults: defaults)
        let config = store.httpConfig()

        XCTAssertEqual(config?.endpoint.absoluteString, "https://example.com/translate")
        XCTAssertEqual(config?.apiKey, "secret")
        XCTAssertEqual(config?.model, "atlas-test")
    }

    func testConfigurationIgnoresInvalidEndpoint() {
        defaults.set("not a url", forKey: ScreenshotTranslationConfigurationKeys.endpoint)

        let store = ScreenshotTranslationConfigurationStore(defaults: defaults)

        XCTAssertNil(store.httpConfig())
    }

    func testConfiguredServiceUsesFallbackWithoutEndpoint() {
        let store = ScreenshotTranslationConfigurationStore(defaults: defaults)
        let service = ConfiguredScreenshotTranslationService(
            configuration: store.httpConfig,
            providerFactory: { _ in FailingTranslationProvider() },
            fallback: LocalPlaceholderScreenshotTranslationService()
        )

        XCTAssertThrowsError(try service.translate("Hola", targetLanguage: "English")) { error in
            XCTAssertEqual(error.localizedDescription, "Local screenshot translation is not supported yet")
        }
    }

    func testConfiguredServiceUsesHTTPProviderWhenEndpointExists() throws {
        defaults.set("https://example.com/translate", forKey: ScreenshotTranslationConfigurationKeys.endpoint)
        let store = ScreenshotTranslationConfigurationStore(defaults: defaults)
        let provider = CapturingConfiguredTranslationProvider(
            result: ScreenshotTranslationResult(sourceText: "Hola", translatedText: "Hello", targetLanguage: "English")
        )
        let service = ConfiguredScreenshotTranslationService(
            configuration: store.httpConfig,
            providerFactory: { config in
                provider.receivedConfig = config
                return provider
            },
            fallback: LocalPlaceholderScreenshotTranslationService()
        )

        let result = try service.translate("Hola", targetLanguage: "English")

        XCTAssertEqual(provider.receivedConfig?.endpoint.absoluteString, "https://example.com/translate")
        XCTAssertEqual(provider.receivedRequest, ScreenshotTranslationRequest(sourceText: "Hola", targetLanguage: "English"))
        XCTAssertEqual(result.translatedText, "Hello")
    }
}

private struct FailingTranslationProvider: ScreenshotTranslationProviding {
    func translate(_ request: ScreenshotTranslationRequest) throws -> ScreenshotTranslationResult {
        XCTFail("Provider should not be used without endpoint configuration")
        return ScreenshotTranslationResult(sourceText: request.sourceText, translatedText: "", targetLanguage: request.targetLanguage)
    }
}

private final class CapturingConfiguredTranslationProvider: ScreenshotTranslationProviding {
    let result: ScreenshotTranslationResult
    var receivedConfig: HTTPTranslationEndpointConfig?
    private(set) var receivedRequest: ScreenshotTranslationRequest?

    init(result: ScreenshotTranslationResult) {
        self.result = result
    }

    func translate(_ request: ScreenshotTranslationRequest) throws -> ScreenshotTranslationResult {
        receivedRequest = request
        return result
    }
}
```

- [x] **Step 2: Add test file to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `ScreenshotTranslationConfigurationTests.swift` is listed in:

```text
PBXFileReference
PBXBuildFile
AtlasTests group
AtlasTests Sources build phase
```

- [x] **Step 3: Run configuration tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests
```

Expected: FAIL with missing `ScreenshotTranslationConfigurationStore`, `ScreenshotTranslationConfigurationKeys`, `ConfiguredScreenshotTranslationService`, and `ScreenshotTranslationServiceFactory`.

- [x] **Step 4: Add configuration implementation**

Create `platforms/macos/Atlas/ScreenshotTranslationConfiguration.swift`:

```swift
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
```

- [x] **Step 5: Add app source file to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `ScreenshotTranslationConfiguration.swift` is listed in:

```text
PBXFileReference
PBXBuildFile
Atlas group
Atlas Sources build phase
```

- [x] **Step 6: Update AtlasBridge live default**

In `platforms/macos/Atlas/AtlasBridge.swift`, change the translation service default from:

```swift
static var translationService: ScreenshotTranslating = LocalPlaceholderScreenshotTranslationService()
```

to:

```swift
static var translationService: ScreenshotTranslating = ScreenshotTranslationServiceFactory.live()
```

- [x] **Step 7: Run configuration tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests
```

Expected: PASS, 5 tests.

- [x] **Step 8: Run existing translation service tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationServiceTests
```

Expected: PASS. If `tearDown` still resets to `LocalPlaceholderScreenshotTranslationService()`, update it to:

```swift
override func tearDown() {
    AtlasBridge.translationService = ScreenshotTranslationServiceFactory.live()
    super.tearDown()
}
```

and rerun the command until it passes.

- [x] **Step 9: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotTranslationConfiguration.swift \
  platforms/macos/Atlas/AtlasBridge.swift \
  platforms/macos/AtlasTests/ScreenshotTranslationConfigurationTests.swift \
  platforms/macos/AtlasTests/ScreenshotTranslationServiceTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): configure screenshot translation service"
```

---

### Task 4: Final Verification and Plan Notes

**Files:**
- Modify: `docs/superpowers/plans/2026-05-20-translation-engine-v1.md`

- [x] **Step 1: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [x] **Step 2: Run focused translation tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationServiceTests -only-testing:AtlasTests/ScreenshotHTTPTranslationProviderTests -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests
```

Expected: PASS.

- [x] **Step 3: Run full macOS tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected: PASS. The existing CoreSimulator out-of-date warning is acceptable if macOS tests run and `TEST SUCCEEDED` appears.

- [x] **Step 4: Run Rust core tests**

Run:

```bash
cargo test -p atlas-core
```

Expected: PASS.

- [x] **Step 5: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-20-translation-engine-v1.md`:

```markdown
---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
- Focused translation tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationServiceTests -only-testing:AtlasTests/ScreenshotHTTPTranslationProviderTests -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests`
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Rust core tests: `cargo test -p atlas-core`

Translation Engine v1 is intentionally Atlas-compatible HTTP only. Provider-specific adapters, Keychain-backed secrets, and settings UI remain future work.
```

- [x] **Step 6: Commit verification notes**

```bash
git add docs/superpowers/plans/2026-05-20-translation-engine-v1.md
git commit -m "docs: record translation engine v1 verification"
```

---

## Self-Review

1. **Spec coverage:** The plan implements provider abstraction, HTTP provider, configuration-backed live service, tests, verification, and keeps the current UI call path. It deliberately excludes settings UI, provider-specific adapters, Keychain, streaming, and multi-engine comparison.
2. **Placeholder scan:** No task uses incomplete placeholder instructions. Each implementation step includes concrete code or exact project-file edit intent.
3. **Type consistency:** `ScreenshotTranslationRequest`, `ScreenshotTranslationProviding`, `ProviderBackedScreenshotTranslationService`, `HTTPTranslationEndpointConfig`, `HTTPTranslationTransporting`, `ScreenshotHTTPTranslationProvider`, `ScreenshotTranslationConfigurationStore`, `ConfiguredScreenshotTranslationService`, and `ScreenshotTranslationServiceFactory` are introduced before later tasks use them.

---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
- Focused translation tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationServiceTests -only-testing:AtlasTests/ScreenshotHTTPTranslationProviderTests -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests`
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Rust core tests: `cargo test -p atlas-core`

Translation Engine v1 is intentionally Atlas-compatible HTTP only. Provider-specific adapters, Keychain-backed secrets, and settings UI remain future work.
