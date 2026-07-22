import XCTest
@testable import Atlas

private struct StubSource: LauncherItemSource {
    let sourceID: String
    let itemsByQuery: (String) -> [LauncherItem]
    func items(for query: String) -> [LauncherItem] { itemsByQuery(query) }
}

private func makeItem(
    title: String,
    category: String,
    isAnswer: Bool = false
) -> LauncherItem {
    LauncherItem(
        id: "\(category)|\(title)",
        title: title,
        icon: .sfSymbol("bolt"),
        category: category,
        actions: [LauncherAction(id: "run", title: "Run", systemImage: "return") { .dismiss }],
        isAnswer: isAnswer
    )
}

private struct StubAliases: AliasResolving {
    let mapping: [String: String]
    func commandKey(matching query: String) -> String? {
        mapping.first { query == $0.key || $0.key.hasPrefix(query) }?.value
    }
}

final class LauncherSectionBuilderTests: XCTestCase {
    private let toolA = makeItem(title: "Alpha", category: "Tools")
    private let toolB = makeItem(title: "Beta", category: "Tools")
    private let appX = makeItem(title: "Xcode", category: "Applications")

    private func source(_ items: [LauncherItem]) -> LauncherItemSource {
        StubSource(sourceID: "stub", itemsByQuery: { _ in items })
    }

    func testEmptyQueryShowsFavoritesThenRecentsThenCategories() {
        let records = [
            "Tools|Beta": CommandUsageRecord(commandKey: "Tools|Beta", executionCount: 5, lastExecutedAt: Date()),
        ]
        let sections = LauncherSectionBuilder.build(
            query: "",
            sources: [source([toolA, toolB, appX])],
            favorites: ["Applications|Xcode"],
            records: records
        )

        XCTAssertEqual(sections[0].id, .favorites)
        XCTAssertEqual(sections[0].items.map(\.id), ["Applications|Xcode"])
        XCTAssertEqual(sections[1].id, .recents)
        XCTAssertEqual(sections[1].items.map(\.id), ["Tools|Beta"])
        XCTAssertEqual(sections[2].id, .results("Tools"))
        XCTAssertEqual(sections[2].items.map(\.id), ["Tools|Alpha"])
    }

    func testAnswerItemFirst() {
        let answer = makeItem(title: "2+2", category: "Calculator", isAnswer: true)
        let sections = LauncherSectionBuilder.build(
            query: "2+2",
            sources: [source([toolA, answer])],
            favorites: [],
            records: [:]
        )
        XCTAssertEqual(sections[0].id, .answer)
        XCTAssertEqual(sections[0].items.first?.title, "2+2")
    }

    func testFallbackAppendedForNonEmptyQuery() {
        let fallback = makeItem(title: "Search Google", category: "Fallback")
        let sections = LauncherSectionBuilder.build(
            query: "zzz",
            sources: [source([])],
            favorites: [],
            records: [:],
            fallbackItems: [fallback]
        )
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].id, .fallback)
        XCTAssertEqual(sections[0].title, "Use \"zzz\" with…")
    }

    func testNoFallbackOnEmptyQuery() {
        let fallback = makeItem(title: "Search Google", category: "Fallback")
        let sections = LauncherSectionBuilder.build(
            query: "",
            sources: [source([toolA])],
            favorites: [],
            records: [:],
            fallbackItems: [fallback]
        )
        XCTAssertFalse(sections.contains { $0.id == .fallback })
    }

    func testDedupeAcrossSections() {
        let sections = LauncherSectionBuilder.build(
            query: "alpha",
            sources: [source([toolA])],
            favorites: ["Tools|Alpha"],
            records: [:]
        )
        // Pinned match floats to favorites; results section must not repeat it.
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].id, .favorites)
    }

    func testEmptySourceIsolated() {
        let empty = StubSource(sourceID: "empty", itemsByQuery: { _ in [] })
        let sections = LauncherSectionBuilder.build(
            query: "",
            sources: [empty, source([toolA])],
            favorites: [],
            records: [:]
        )
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].items.map(\.id), ["Tools|Alpha"])
    }

    func testNonMatchingItemsFilteredOut() {
        // provider 匹配过宽:查询 "anti" 却返回 Capture 命令 → 兜底过滤应剔除。
        let loose = StubSource(sourceID: "loose") { _ in [self.toolA, self.toolB] }
        let sections = LauncherSectionBuilder.build(
            query: "anti",
            sources: [loose],
            favorites: [],
            records: [:]
        )
        XCTAssertTrue(sections.isEmpty)
    }

    func testAliasMatchPrependsItem() {
        let rootSource = StubSource(sourceID: "stub") { query in
            query.isEmpty ? [self.toolA, self.toolB] : []
        }
        let sections = LauncherSectionBuilder.build(
            query: "aa",
            sources: [rootSource],
            favorites: [],
            records: [:],
            aliases: StubAliases(mapping: ["aa": "Tools|Alpha"])
        )
        XCTAssertEqual(sections.first?.items.map(\.id), ["Tools|Alpha"])
    }

    func testEmptyRootCandidatesFallBackToProviderFiltered() {
        // provider 空查询返回空、有查询才吐结果(AppLauncher 型):必须仍可搜到。
        let providerStyle = StubSource(sourceID: "apps") { query in
            query.isEmpty ? [] : [self.toolA]
        }
        let sections = LauncherSectionBuilder.build(
            query: "alpha",
            sources: [providerStyle],
            favorites: [],
            records: [:]
        )
        XCTAssertEqual(sections.flatMap(\.items).map(\.id), ["Tools|Alpha"])
    }

    func testSearchIsGloballyRankedSingleSection() {
        let sections = LauncherSectionBuilder.build(
            query: "a",
            sources: [source([toolA, appX])],
            favorites: [],
            records: [:]
        )
        // 非空查询:一个「结果」区,跨分类合并。
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].id, .results("Results"))
        XCTAssertEqual(Set(sections[0].items.map(\.category)), ["Tools", "Applications"])
    }
}
