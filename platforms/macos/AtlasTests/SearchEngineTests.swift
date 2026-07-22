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

    func testCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "CAP", candidate: "capture"))
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

    private func item(_ title: String, keywords: [String] = []) -> LauncherItem {
        LauncherItem(
            id: "T|\(title)", title: title, icon: .sfSymbol("bolt"),
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
}
