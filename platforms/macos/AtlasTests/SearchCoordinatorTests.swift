import XCTest
import Darwin
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

private struct BlockingFastStub: LauncherItemSource {
    let sourceID = "blocking-fast"
    func items(for query: String) -> [LauncherItem] {
        Thread.sleep(forTimeInterval: 0.15)
        return [
            LauncherItem(id: "T|Delayed", title: "Delayed", icon: .sfSymbol("bolt"),
                         category: "T", actions: []),
        ]
    }
}

private struct RefiningFastStub: LauncherItemSource {
    let sourceID = "refining-fast"

    func items(for query: String) -> [LauncherItem] {
        if query.count > 1 {
            Thread.sleep(forTimeInterval: 0.15)
        }
        return [
            LauncherItem(
                id: "T|\(query)",
                title: query,
                icon: .sfSymbol("bolt"),
                category: "T",
                actions: [],
                acceptsArgument: true
            ),
        ]
    }
}

private struct SlowStub: LauncherItemSource, AsyncLauncherItemSource {
    let sourceID: String
    let delay: TimeInterval
    let isSlow = true
    let searchMode: SourceSearchMode = .queryDriven

    func items(for query: String) -> [LauncherItem] { [] }

    func itemsAsync(for query: String) async -> [LauncherItem] {
        // Deliberately non-cooperative to prove generation guards, rather than
        // Task.sleep cancellation, prevent stale publication.
        usleep(useconds_t(delay * 1_000_000))
        return [
            LauncherItem(
                id: "\(sourceID)|\(query)",
                title: "\(sourceID) \(query)",
                icon: .sfSymbol("bolt"),
                category: "Slow",
                actions: [],
                acceptsArgument: true
            ),
        ]
    }
}

@MainActor
final class SearchCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        sources: [LauncherItemSource] = [FastStub()]
    ) -> LauncherSearchCoordinator {
        LauncherSearchCoordinator(
            sources: sources,
            favorites: { [] },
            records: {
                ["T|Capture Area": CommandUsageRecord(
                    commandKey: "T|Capture Area",
                    executionCount: 3,
                    lastExecutedAt: Date()
                )]
            },
            fallbackItems: { _ in [] },
            aliases: nil,
            aliasName: { _ in nil }
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    func testEmptyQueryShowsRecents() async {
        let coordinator = makeCoordinator()
        coordinator.updateQuery("")
        let appeared = await waitUntil {
            coordinator.sections.contains { $0.id == .recents }
        }
        XCTAssertTrue(appeared)
    }

    func testTypedQueryReplacesRecentsWithMatches() async {
        let coordinator = makeCoordinator()
        coordinator.updateQuery("")
        coordinator.updateQuery("finder")
        let appeared = await waitUntil {
            coordinator.sections.flatMap(\.items).map(\.title) == ["Finder Thing"]
        }
        XCTAssertTrue(appeared)
        XCTAssertFalse(coordinator.sections.contains { $0.id == .recents },
                       "typed query must not show recents; got \(coordinator.sections.map(\.title))")
    }

    func testNoMatchesEmptySections() async {
        let coordinator = makeCoordinator()
        coordinator.updateQuery("finder")
        _ = await waitUntil {
            coordinator.sections.flatMap(\.items).contains { $0.title == "Finder Thing" }
        }
        coordinator.updateQuery("zzzz")
        let cleared = await waitUntil {
            coordinator.sections.flatMap(\.items).isEmpty
        }
        XCTAssertTrue(cleared)
    }

    func testUpdateQueryDoesNotRunBlockingProviderOnMainActor() async {
        let coordinator = makeCoordinator(sources: [BlockingFastStub()])
        let started = Date()
        coordinator.updateQuery("delayed")
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.05)
        let appeared = await waitUntil(timeout: 1) {
            coordinator.sections.flatMap(\.items).contains { $0.title == "Delayed" }
        }
        XCTAssertTrue(appeared)
    }

    func testRefinedQueryKeepsPreviousResultsUntilAtomicReplacement() async {
        let coordinator = makeCoordinator(sources: [RefiningFastStub()])
        coordinator.updateQuery("a")
        let firstAppeared = await waitUntil {
            coordinator.sections.flatMap(\.items).map(\.title) == ["a"]
        }
        XCTAssertTrue(firstAppeared)

        coordinator.updateQuery("ab")
        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.title), ["a"])

        let replacementAppeared = await waitUntil {
            coordinator.sections.flatMap(\.items).map(\.title) == ["ab"]
        }
        XCTAssertTrue(replacementAppeared)
    }

    func testSlowSourcesRunConcurrently() async {
        let coordinator = makeCoordinator(sources: [
            FastStub(),
            SlowStub(sourceID: "one", delay: 0.2),
            SlowStub(sourceID: "two", delay: 0.2),
        ])
        let started = Date()
        coordinator.updateQuery("query")
        let bothAppeared = await waitUntil(timeout: 0.65) {
            let titles = Set(coordinator.sections.flatMap(\.items).map(\.title))
            return titles.contains("one query") && titles.contains("two query")
        }
        XCTAssertTrue(bothAppeared)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.55,
                          "two 200ms sources plus 150ms debounce should run concurrently")
    }

    func testOldGenerationCannotOverwriteNewQuery() async {
        let coordinator = makeCoordinator(sources: [
            SlowStub(sourceID: "slow", delay: 0.25),
        ])
        coordinator.updateQuery("old")
        try? await Task.sleep(nanoseconds: 180_000_000)
        coordinator.updateQuery("new")

        let newAppeared = await waitUntil(timeout: 0.8) {
            coordinator.sections.flatMap(\.items).contains { $0.title == "slow new" }
        }
        XCTAssertTrue(newAppeared)
        XCTAssertFalse(coordinator.sections.flatMap(\.items).contains { $0.title == "slow old" })
    }
}
