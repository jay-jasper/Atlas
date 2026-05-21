import XCTest
@testable import Atlas

final class DeveloperToolsProviderTests: XCTestCase {
    func testEmptyQueryReturnsNoResults() {
        let provider = makeProvider()

        XCTAssertTrue(provider.results(for: " \n ").isEmpty)
    }

    func testDeveloperQueryReturnsDeveloperCommands() {
        let provider = makeProvider()
        let results = provider.results(for: "dev")

        XCTAssertEqual(results.map(\.title), [
            "Open Terminal",
            "Open Activity Monitor",
            "Open Console",
        ])
    }

    func testActivityQueryMatchesActivityMonitor() {
        let provider = makeProvider()
        let results = provider.results(for: "activity")

        XCTAssertEqual(results.map(\.title), ["Open Activity Monitor"])
    }

    func testConsoleQueryMatchesConsole() {
        let provider = makeProvider()
        let results = provider.results(for: "console")

        XCTAssertEqual(results.map(\.title), ["Open Console"])
    }

    func testTerminalQueryMatchesTerminal() {
        let provider = makeProvider()
        let results = provider.results(for: "terminal")

        XCTAssertEqual(results.map(\.title), ["Open Terminal"])
    }

    func testAllResultsHaveDeveloperCategoryAndHammerIcon() {
        let provider = makeProvider()
        let results = provider.results(for: "dev")

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.category == "Developer" })
        XCTAssertTrue(results.allSatisfy { $0.icon == .sfSymbol("hammer") })
    }

    func testExecutingResultCallsInjectedAction() {
        var opened: [String] = []
        let provider = DeveloperToolsProvider(
            openTerminal: { opened.append("terminal") },
            openActivityMonitor: { opened.append("activity") },
            openConsole: { opened.append("console") }
        )

        let result = provider.results(for: "terminal").first
        if case .execute(let execute)? = result?.action {
            execute()
        } else {
            XCTFail("expected executable developer tool result")
        }

        XCTAssertEqual(opened, ["terminal"])
    }

    func testResultsAreCappedToFixedSmallCount() {
        let provider = makeProvider()
        let results = provider.results(for: "dev")

        XCTAssertLessThanOrEqual(results.count, 5)
    }

    private func makeProvider() -> DeveloperToolsProvider {
        DeveloperToolsProvider(
            openTerminal: {},
            openActivityMonitor: {},
            openConsole: {}
        )
    }
}
