import XCTest
@testable import Atlas

@MainActor
final class SearchProbeTests: XCTestCase {
    func testAntiDoesNotMatchCaptureCommands() {
        let provider = AtlasCommandProvider(
            onScreenshot: {}, onScreenRecording: {}, onOpenSettings: {}
        )
        let adapter = CommandProviderAdapter(provider: provider, sourceID: "atlas")
        let sections = LauncherSectionBuilder.build(
            query: "anti", sources: [adapter], favorites: [], records: [:]
        )
        XCTAssertTrue(sections.isEmpty, "got: \(sections.flatMap(\.items).map(\.title))")
    }

    func testFinderDoesNotMatchCaptureEvenWithUsageRecords() {
        // 用户实拍 bug:输入 finder 出现 Capture Area/Desktop。
        // frecency 权重不得把不匹配的高频命令顶回结果。
        let provider = AtlasCommandProvider(
            onScreenshot: {}, onScreenRecording: {}, onOpenSettings: {}
        )
        let adapter = CommandProviderAdapter(provider: provider, sourceID: "atlas")
        let ids = adapter.items(for: "").map(\.id)
        let records = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, CommandUsageRecord(commandKey: $0, executionCount: 50, lastExecutedAt: Date()))
        })
        let sections = LauncherSectionBuilder.build(
            query: "finder", sources: [adapter], favorites: [], records: records
        )
        let titles = sections.flatMap(\.items).map(\.title)
        XCTAssertTrue(titles.isEmpty, "finder must not match capture commands, got: \(titles)")
        XCTAssertFalse(sections.contains { $0.id == .recents }, "recents must not render with query")
    }

    func testSparseFuzzyQueryDoesNotMatchUnrelatedLongTitles() {
        let items = [
            LauncherItem(
                id: "app",
                title: "TablePlus",
                subtitle: nil,
                icon: .sfSymbol("app"),
                keywords: [],
                category: "Application",
                actions: []
            ),
            LauncherItem(
                id: "snippet",
                title: "Copy Meeting Notes",
                subtitle: nil,
                icon: .sfSymbol("quote.bubble"),
                keywords: [],
                category: "Snippet",
                actions: []
            ),
        ]

        let matches = LauncherSearchEngine.annotate(items: items, query: "tes", records: [:])
        XCTAssertTrue(
            matches.isEmpty,
            "sparse fuzzy matches must be rejected, got: \(matches.map(\.title))"
        )
    }

    func testFileSearchNoPrefixNeeded() {
        let provider = FileSearchProvider(
            open: { _ in },
            syncSearch: { _, _ in
                [
                    "/Users/x/deep/notes-finder.txt",
                    "/Users/x/finder-notes.md",
                    "/Users/x/App.app",
                ]
            }
        )
        let results = provider.results(for: "finder")
        XCTAssertEqual(results.map(\.title), ["finder-notes.md", "notes-finder.txt"],
                       "prefix hit first, .app excluded, no 'f ' prefix required")
    }

    func testAsyncFileSearchIsBoundedToDisplayedResults() async {
        let provider = FileSearchProvider(
            open: { _ in },
            asyncSearch: { _, limit in
                (0..<(limit + 100)).map { "/tmp/result-\($0).txt" }
            }
        )
        let results = await provider.resultsAsync(for: "result")
        XCTAssertEqual(results.count, 6)
    }

    func testAsyncFileSearchHonorsTaskCancellation() async {
        let provider = FileSearchProvider(
            open: { _ in },
            asyncSearch: { _, _ in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return ["/tmp/should-not-publish.txt"]
            }
        )
        let started = Date()
        let task = Task { await provider.resultsAsync(for: "publish") }
        task.cancel()
        let results = await task.value
        XCTAssertTrue(results.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
    }
}
