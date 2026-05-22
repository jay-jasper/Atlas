import XCTest
@testable import Atlas

final class TokenBarCommandProviderTests: XCTestCase {
    func testImportCommandCallsImporterRefreshesSummaryAndSurfacesSuccess() {
        var openedSettings = false
        var refreshedSummary: TokenBarSummary?
        var statusMessages: [(String, TokenBarCommandStatusKind)] = []
        let provider = TokenBarCommandProvider(
            isEnabled: { true },
            onOpenSettings: { openedSettings = true },
            importer: StubTokenBarUsageImporter(summary: TokenBarSummary(inputTokens: 10, outputTokens: 4, costMicrosUSD: 7)),
            onRefreshSummary: { refreshedSummary = $0 },
            onShowStatus: { statusMessages.append(($0, $1)) }
        )

        let commands = provider.results(for: "token")

        XCTAssertEqual(commands.map(\.title), ["Open TokenBar", "Import Token Usage", "TokenBar Settings"])
        if case .push(.tokenBar) = commands[0].action {} else { XCTFail("Expected tokenBar destination") }
        if case let .execute(importAction) = commands[1].action { importAction() } else { XCTFail("Expected import execute action") }
        if case let .execute(settingsAction) = commands[2].action { settingsAction() } else { XCTFail("Expected settings execute action") }
        XCTAssertEqual(refreshedSummary, TokenBarSummary(inputTokens: 10, outputTokens: 4, costMicrosUSD: 7))
        XCTAssertEqual(statusMessages.first?.0, "Imported token usage")
        XCTAssertEqual(statusMessages.first?.1, .success)
        XCTAssertTrue(openedSettings)
    }

    func testImportCommandSurfacesImporterError() {
        var statusMessages: [(String, TokenBarCommandStatusKind)] = []
        let provider = TokenBarCommandProvider(
            isEnabled: { true },
            onOpenSettings: {},
            importer: StubTokenBarUsageImporter(error: CocoaError(.fileReadCorruptFile)),
            onRefreshSummary: { _ in XCTFail("Should not refresh on failure") },
            onShowStatus: { statusMessages.append(($0, $1)) }
        )

        let command = provider.results(for: "import").first { $0.title == "Import Token Usage" }
        if case let .execute(importAction) = command?.action { importAction() } else { XCTFail("Expected import execute action") }

        XCTAssertEqual(statusMessages.first?.1, .error)
    }

    func testCommandsAreHiddenWhenFeatureDisabled() {
        let provider = TokenBarCommandProvider(
            isEnabled: { false },
            onOpenSettings: {},
            importer: StubTokenBarUsageImporter(),
            onRefreshSummary: { _ in },
            onShowStatus: { _, _ in }
        )

        XCTAssertEqual(provider.results(for: "token").count, 0)
    }
}

struct StubTokenBarUsageImporter: TokenBarUsageImporting {
    var summary: TokenBarSummary = .empty
    var error: Error?

    func importUsage() throws -> TokenBarSummary {
        if let error { throw error }
        return summary
    }
}
