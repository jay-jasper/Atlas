import XCTest
@testable import Atlas

final class TokenBarProviderUsageImporterTests: XCTestCase {
    func testImportFetchesProviderUsageAppendsLedgerAndReturnsUpdatedSummary() throws {
        let defaults = UserDefaults(suiteName: "TokenBarProviderUsageImporterTests.import")!
        defaults.removePersistentDomain(forName: "TokenBarProviderUsageImporterTests.import")
        let keychain = InMemoryTokenBarSecretStore()
        let configStore = TokenBarConfigurationStore(defaults: defaults, secretStore: keychain)
        configStore.save(TokenBarProviderConfiguration(
            provider: .openAI,
            displayName: "Work",
            endpoint: URL(string: "https://api.openai.com")!,
            apiKey: "sk-test",
            defaultModel: "gpt-4.1-mini"
        ))
        let ledgerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let ledger = TokenBarLedger(fileURL: ledgerURL)
        try ledger.append(TokenBarUsageEntry(
            provider: .openAI,
            model: "gpt-4.1-mini",
            inputTokens: 1,
            outputTokens: 2,
            costMicrosUSD: 3,
            recordedAt: Date(timeIntervalSince1970: 1),
            source: "manual"
        ))
        let response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let transport = CapturingTokenBarTransport(
            data: Data(#"{"input_tokens":10,"output_tokens":4}"#.utf8),
            response: response
        )
        let importer = TokenBarProviderUsageImporter(
            configStore: configStore,
            ledger: ledger,
            client: TokenBarProviderClient(transport: transport),
            now: { Date(timeIntervalSince1970: 42) }
        )

        let summary = try importer.importUsage()

        XCTAssertEqual(try ledger.load().map(\.source), ["manual", "provider"])
        XCTAssertEqual(summary.inputTokens, 11)
        XCTAssertEqual(summary.outputTokens, 6)
        XCTAssertGreaterThan(summary.costMicrosUSD, 3)
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testImportFailsWithoutConfiguration() {
        let defaults = UserDefaults(suiteName: "TokenBarProviderUsageImporterTests.missing")!
        defaults.removePersistentDomain(forName: "TokenBarProviderUsageImporterTests.missing")
        let response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let importer = TokenBarProviderUsageImporter(
            configStore: TokenBarConfigurationStore(defaults: defaults, secretStore: InMemoryTokenBarSecretStore()),
            ledger: TokenBarLedger(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json")
            ),
            client: TokenBarProviderClient(transport: CapturingTokenBarTransport(data: Data(), response: response)),
            now: Date.init
        )

        XCTAssertThrowsError(try importer.importUsage())
    }
}
