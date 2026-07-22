import XCTest
@testable import Atlas

private struct FastStub: LauncherItemSource {
    let sourceID = "fast"
    func items(for query: String) -> [LauncherItem] {
        [
            LauncherItem(id: "T|Capture Area", title: "Capture Area", icon: .sfSymbol("bolt"),
                         category: "T", actions: []),
            LauncherItem(id: "T|Finder Thing", title: "Finder Thing", icon: .sfSymbol("bolt"),
                         category: "T", actions: []),
        ]
    }
}

@MainActor
final class SearchCoordinatorTests: XCTestCase {
    private func makeCoordinator() -> LauncherSearchCoordinator {
        LauncherSearchCoordinator(
            sources: [FastStub()],
            favorites: { [] },
            records: { ["T|Capture Area": CommandUsageRecord(commandKey: "T|Capture Area", executionCount: 3, lastExecutedAt: Date())] },
            fallbackItems: { _ in [] },
            aliases: nil,
            aliasName: { _ in nil }
        )
    }

    func testEmptyQueryShowsRecents() {
        let coordinator = makeCoordinator()
        coordinator.updateQuery("")
        XCTAssertTrue(coordinator.sections.contains { $0.id == .recents })
    }

    func testTypedQueryReplacesRecentsWithMatches() {
        let coordinator = makeCoordinator()
        coordinator.updateQuery("")
        coordinator.updateQuery("finder")
        XCTAssertFalse(coordinator.sections.contains { $0.id == .recents },
                       "typed query must not show recents; got \(coordinator.sections.map(\.title))")
        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.title), ["Finder Thing"])
    }

    func testNoMatchesEmptySections() {
        let coordinator = makeCoordinator()
        coordinator.updateQuery("zzzz")
        XCTAssertTrue(coordinator.sections.flatMap(\.items).isEmpty)
    }
}
