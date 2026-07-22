import Foundation

struct LauncherSectionData: Identifiable {
    let id: LauncherSection
    let title: String
    let items: [LauncherItem]
}

enum LauncherSectionBuilder {
    /// 按源模式产出条目:commandList 走引擎(模糊+拼音+frecency),
    /// queryDriven 原样传 query + 相关性兜底。
    static func process(
        sources: [LauncherItemSource],
        query: String,
        records: [String: CommandUsageRecord],
        now: Date = Date()
    ) -> [LauncherItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var items: [LauncherItem] = []
        for source in sources {
            switch source.searchMode {
            case .commandList:
                // 候选 = 空查询全量 ∪ provider 自筛结果(部分 provider 空查询返回空,
                // 只有喂 query 才吐候选;两路并集去重后交给引擎)。
                var pool = source.items(for: "")
                var seenIDs = Set(pool.map(\.id))
                var providerMatched: [LauncherItem] = []
                if !trimmed.isEmpty {
                    providerMatched = source.items(for: trimmed)
                    for item in providerMatched where !seenIDs.contains(item.id) {
                        pool.append(item)
                        seenIDs.insert(item.id)
                    }
                }
                // 引擎统一裁决(子序列+拼音,比 provider 的 contains 更宽):
                // provider 匹配过宽的条目在这里被正确剔除。
                _ = providerMatched
                let annotated = LauncherSearchEngine.annotate(
                    items: pool,
                    query: trimmed,
                    records: records,
                    now: now
                )
                items.append(contentsOf: annotated)
            case .queryDriven:
                var raw = source.items(for: trimmed)
                if !trimmed.isEmpty {
                    raw = raw.filter { item in
                        item.isAnswer || item.acceptsArgument || Self.matches(item, query: trimmed)
                    }
                }
                items.append(contentsOf: raw)
            }
        }
        return items
    }

    static func build(
        query: String,
        sources: [LauncherItemSource],
        favorites: [String],
        records: [String: CommandUsageRecord],
        fallbackItems: [LauncherItem] = [],
        aliases: AliasResolving? = nil,
        recentsLimit: Int = 5
    ) -> [LauncherSectionData] {
        assemble(
            items: process(sources: sources, query: query, records: records),
            query: query,
            aliasLookup: { key in
                (aliases as? AliasStore).flatMap { alias in
                    MainActor.assumeIsolated { alias.alias(for: key) }
                }
            },
            resolveAliasItems: { trimmed in
                guard let aliases,
                      let aliasedKey = aliases.commandKey(matching: trimmed.lowercased()) else { return [] }
                return sources.flatMap { $0.items(for: "") }.filter { $0.id == aliasedKey }
            },
            favorites: favorites,
            records: records,
            fallbackItems: fallbackItems,
            recentsLimit: recentsLimit
        )
    }

    /// 汇编分区(条目已由 process/coordinator 产出)。
    static func assemble(
        items: [LauncherItem],
        query: String,
        aliasLookup: (String) -> String? = { _ in nil },
        resolveAliasItems: (String) -> [LauncherItem] = { _ in [] },
        favorites: [String],
        records: [String: CommandUsageRecord],
        fallbackItems: [LauncherItem] = [],
        recentsLimit: Int = 5
    ) -> [LauncherSectionData] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var allItems = items.map { item -> LauncherItem in
            var copy = item
            copy.aliasBadge = aliasLookup(item.id)
            return copy
        }
        _ = allItems

        var sections: [LauncherSectionData] = []
        var seen = Set<String>()

        func appendSection(_ id: LauncherSection, title: String, items: [LauncherItem]) {
            let fresh = items.filter { seen.insert($0.id).inserted }
            guard !fresh.isEmpty else { return }
            sections.append(LauncherSectionData(id: id, title: title, items: fresh))
        }

        // Alias exact/prefix hit resolves the aliased command to the very top.
        let aliasItems: [LauncherItem] = trimmed.isEmpty ? [] : resolveAliasItems(trimmed)

        // Answer card (calculator/conversion) comes first.
        if let answer = (aliasItems + allItems).first(where: { $0.isAnswer }) {
            appendSection(.answer, title: "", items: [answer])
        }

        if !aliasItems.isEmpty {
            appendSection(.favorites, title: "Alias", items: aliasItems)
        }

        if trimmed.isEmpty {
            // Root: Favorites → Recents → per-category results.
            let byID = Dictionary(grouping: allItems, by: \.id).compactMapValues(\.first)
            let favoriteItems = favorites.compactMap { byID[$0] }
            appendSection(.favorites, title: "Favorites", items: favoriteItems)

            let recentItems = records.values
                .sorted {
                    if $0.executionCount != $1.executionCount {
                        return $0.executionCount > $1.executionCount
                    }
                    return $0.lastExecutedAt > $1.lastExecutedAt
                }
                .compactMap { byID[$0.commandKey] }
                .prefix(recentsLimit)
            appendSection(.recents, title: "Recents", items: Array(recentItems))
        } else {
            // Search: matching pinned items float into a Favorites section first.
            let pinnedMatches = allItems.filter { favorites.contains($0.id) && !$0.isAnswer }
            appendSection(.favorites, title: "Favorites", items: pinnedMatches)
        }

        if trimmed.isEmpty {
            // 根页:仍按分类分组浏览。
            let grouped = Dictionary(grouping: allItems.filter { !$0.isAnswer }, by: \.category)
            let categoryOrder = allItems.map(\.category).uniqued()
            for category in categoryOrder {
                guard let categoryItems = grouped[category] else { continue }
                appendSection(.results(category), title: category, items: categoryItems)
            }
        } else {
            // 搜索:Raycast 式全局单列表,按综合分排序;分类只做行尾徽标。
            let ranked = allItems.filter { !$0.isAnswer }
                .enumerated()
                .sorted { lhs, rhs in
                    if lhs.element.searchScore != rhs.element.searchScore {
                        return lhs.element.searchScore > rhs.element.searchScore
                    }
                    return lhs.offset < rhs.offset
                }
                .map(\.element)
            appendSection(.results("Results"), title: "结果", items: ranked)
        }

        if !trimmed.isEmpty, !fallbackItems.isEmpty {
            appendSection(.fallback, title: "Use \"\(trimmed)\" with…", items: fallbackItems)
        }

        return sections
    }

    /// 标题 / 副标题 / 关键词 任一包含查询即视为匹配。
    static func matches(_ item: LauncherItem, query: String) -> Bool {
        if item.title.localizedCaseInsensitiveContains(query) { return true }
        if let subtitle = item.subtitle, subtitle.localizedCaseInsensitiveContains(query) { return true }
        return item.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
    }

}

/// Implemented by AliasStore (Task 8); protocol lives here so the builder is testable without it.
protocol AliasResolving {
    func commandKey(matching query: String) -> String?
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
