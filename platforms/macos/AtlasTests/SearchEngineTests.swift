import XCTest
@testable import Atlas

final class SearchEngineTests: XCTestCase {
    // MARK: FuzzyMatcher

    func testFullSubsequenceRequired() {
        XCTAssertNil(FuzzyMatcher.match(query: "xyz", candidate: "Capture Area"))
        XCTAssertNotNil(FuzzyMatcher.match(query: "cparea", candidate: "Capture Area"))
    }

    func testBoundaryBeatsScatter() {
        // "ca" 命中 "Capture Area" 词首 vs 散点命中 "vocal band"。
        let boundary = FuzzyMatcher.match(query: "ca", candidate: "Capture Area")!
        let scatter = FuzzyMatcher.match(query: "ca", candidate: "vocal band")!
        XCTAssertGreaterThan(boundary.score, scatter.score)
    }

    func testPositionsAscendingAndCorrect() {
        let result = FuzzyMatcher.match(query: "cw", candidate: "Capture Window")!
        XCTAssertEqual(result.positions, [0, 8])
    }

    func testSmartCase() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "cap", candidate: "CAPTURE"))
        XCTAssertNil(FuzzyMatcher.match(query: "CAP", candidate: "capture"))
        XCTAssertNotNil(FuzzyMatcher.match(query: "CAP", candidate: "CAPTURE"))
    }

    func testV2ChoosesHigherScoringAlignment() {
        let result = FuzzyMatcher.match(query: "ab", candidate: "xabc ab")!
        XCTAssertEqual(result.positions, [5, 6],
                       "V2 should choose the later word-boundary alignment, not the first greedy hit")
    }

    // MARK: Pinyin

    func testPinyinFullAndInitials() {
        let full = PinyinIndexer.bestMatch(query: "jietu", text: "截图")
        XCTAssertNotNil(full)
        XCTAssertEqual(full?.positions, [0, 1])

        let initials = PinyinIndexer.bestMatch(query: "jt", text: "截图")
        XCTAssertNotNil(initials)
        XCTAssertEqual(initials?.positions, [0, 1])
    }

    func testPinyinMixedText() {
        // 中英混合:「区域截图 Area」
        let match = PinyinIndexer.bestMatch(query: "quyu", text: "区域截图")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.positions.first, 0)
    }

    func testNonChineseFallsBackToDirect() {
        let match = PinyinIndexer.bestMatch(query: "cap", text: "Capture")
        XCTAssertNotNil(match)
    }

    // MARK: Frecency

    func testFrecencyDecayHalvesAtSevenDays() {
        let now = Date()
        let fresh = CommandUsageRecord(commandKey: "k", executionCount: 10, lastExecutedAt: now)
        let old = CommandUsageRecord(
            commandKey: "k", executionCount: 10,
            lastExecutedAt: now.addingTimeInterval(-7 * 24 * 3600)
        )
        let freshScore = FrecencyRanker.frecency(fresh, now: now)
        let oldScore = FrecencyRanker.frecency(old, now: now)
        XCTAssertEqual(freshScore, 10, accuracy: 0.01)
        XCTAssertEqual(oldScore, 5, accuracy: 0.01)
        XCTAssertEqual(FrecencyRanker.frecency(nil, now: now), 0)
    }

    // MARK: Engine

    private func item(
        _ title: String,
        subtitle: String? = nil,
        keywords: [String] = []
    ) -> LauncherItem {
        LauncherItem(
            id: "T|\(title)", title: title, subtitle: subtitle, icon: .sfSymbol("bolt"),
            keywords: keywords, category: "T",
            actions: [LauncherAction(id: "run", title: "Run", systemImage: "return") { .dismiss }]
        )
    }

    func testEngineFiltersAndRanks() {
        let items = [item("Capture Area"), item("Nonsense"), item("截图库")]
        let out = LauncherSearchEngine.annotate(items: items, query: "ca", records: [:])
        XCTAssertEqual(out.map(\.title), ["Capture Area"])
        XCTAssertNotNil(out[0].titleHighlightOffsets)
    }

    func testEnginePinyinFindsChineseTitle() {
        let items = [item("截图库"), item("Port Lookup")]
        let out = LauncherSearchEngine.annotate(items: items, query: "jietu", records: [:])
        XCTAssertEqual(out.first?.title, "截图库")
        XCTAssertEqual(out.first?.titleHighlightOffsets, [0, 1])
    }

    func testEngineKeywordHitNoHighlightAndDiscounted() {
        let byTitle = item("Screenshot")
        let byKeyword = item("Other", keywords: ["screenshot"])
        let out = LauncherSearchEngine.annotate(
            items: [byKeyword, byTitle], query: "screenshot", records: [:]
        )
        XCTAssertEqual(out.first?.title, "Screenshot")
        XCTAssertNil(out.first(where: { $0.title == "Other" })?.titleHighlightOffsets ?? nil)
    }

    func testEngineEmptyQueryFrecencyOrder() {
        let now = Date()
        let records = [
            "T|B": CommandUsageRecord(commandKey: "T|B", executionCount: 9, lastExecutedAt: now),
        ]
        let out = LauncherSearchEngine.annotate(
            items: [item("A"), item("B")], query: "", records: records, now: now
        )
        XCTAssertEqual(out.map(\.title), ["B", "A"])
    }

    func testMultiTermMayMatchAcrossFields() {
        let items = [
            item("Open", subtitle: "System Settings"),
            item("Open Project", subtitle: "Workspace"),
        ]
        let out = LauncherSearchEngine.annotate(
            items: items,
            query: "open settings",
            records: [:]
        )
        XCTAssertEqual(out.map(\.title), ["Open"])
    }

    func testCategoryTextIsNotSearchableThroughSubtitleOrKeywords() {
        let settings = LauncherItem(
            id: "System Settings|General",
            title: "通用设置",
            subtitle: "系统设置 · General",
            icon: .sfSymbol("gearshape.2"),
            keywords: ["通用", "General", "系统设置"],
            category: "系统设置",
            actions: []
        )

        XCTAssertTrue(
            LauncherSearchEngine.annotate(
                items: [settings],
                query: "xitong",
                records: [:]
            ).isEmpty
        )
        XCTAssertEqual(
            LauncherSearchEngine.annotate(
                items: [settings],
                query: "general",
                records: [:]
            ).map(\.title),
            ["通用设置"]
        )
    }

    func testExtendedPrefixSuffixExactExcludeAndOR() {
        let items = [
            item("Capture Area", subtitle: "PNG"),
            item("Capture Window", subtitle: "JPG"),
            item("Open Settings", subtitle: "System"),
        ]

        XCTAssertEqual(
            LauncherSearchEngine.annotate(items: items, query: "^Capture !Window", records: [:])
                .map(\.title),
            ["Capture Area"]
        )
        XCTAssertEqual(
            LauncherSearchEngine.annotate(items: items, query: "Area$", records: [:])
                .map(\.title),
            ["Capture Area"]
        )
        XCTAssertEqual(
            LauncherSearchEngine.annotate(items: items, query: "'Settings", records: [:])
                .map(\.title),
            ["Open Settings"]
        )
        XCTAssertEqual(
            Set(LauncherSearchEngine.annotate(items: items, query: "Area|Window", records: [:])
                .map(\.title)),
            Set(["Capture Area", "Capture Window"])
        )
    }

    func testAliasIsSearchableAndTopKIsStable() {
        let items = [item("First"), item("Second"), item("Third")]
        let aliases = ["T|Second": "preferred"]
        let aliasResult = LauncherSearchEngine.annotate(
            items: items,
            query: "preferred",
            records: [:],
            aliasLookup: { aliases[$0] }
        )
        XCTAssertEqual(aliasResult.map(\.title), ["Second"])

        let top = LauncherSearchEngine.annotate(
            items: items,
            query: "",
            records: [:],
            limit: 2,
            preservingIDs: ["T|Third"]
        )
        XCTAssertEqual(top.map(\.title), ["First", "Second", "Third"])
    }

    func testPreparedIndexSearchesFiveThousandCandidatesWithinBudget() {
        let items = (0..<5_000).map {
            item("Command \($0)", subtitle: "Utility action \($0)", keywords: ["tool", "action"])
        }
        let documents = LauncherSearchEngine.documents(for: items)
        let started = Date()
        let hits = LauncherSearchEngine.search(
            documents: documents,
            query: "cmd",
            records: [:],
            limit: 50
        )
        XCTAssertEqual(hits.count, 50)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }
}
