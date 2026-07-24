import Foundation

struct LauncherSectionData: Identifiable {
    let id: LauncherSection
    let title: String
    let items: [LauncherItem]
}

struct LauncherSourceSnapshot {
    let sourceID: String
    let searchMode: SourceSearchMode
    let items: [LauncherItem]
}

enum LauncherSectionBuilder {
    /// Calls providers and captures the candidate pool. This phase is kept
    /// separate from scoring so the coordinator can execute both off MainActor
    /// while taking the tiny alias snapshot between them.
    static func collect(
        sources: [LauncherItemSource],
        query: String
    ) -> [LauncherSourceSnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var snapshots: [LauncherSourceSnapshot] = []
        snapshots.reserveCapacity(sources.count)
        for source in sources {
            if Task.isCancelled { return [] }
            switch source.searchMode {
            case .commandList:
                var pool = source.items(for: "")
                var seenIDs = Set(pool.map(\.id))
                if !trimmed.isEmpty {
                    for item in source.items(for: trimmed) where !seenIDs.contains(item.id) {
                        pool.append(item)
                        seenIDs.insert(item.id)
                    }
                }
                snapshots.append(LauncherSourceSnapshot(
                    sourceID: source.sourceID,
                    searchMode: source.searchMode,
                    items: pool
                ))
            case .queryDriven:
                snapshots.append(LauncherSourceSnapshot(
                    sourceID: source.sourceID,
                    searchMode: source.searchMode,
                    items: source.items(for: trimmed)
                ))
            }
        }
        return snapshots
    }

    static func process(
        snapshots: [LauncherSourceSnapshot],
        query: String,
        records: [String: CommandUsageRecord],
        now: Date = Date(),
        aliasLookup: (String) -> String? = { _ in nil },
        preservingIDs: Set<String> = []
    ) -> [LauncherItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var items: [LauncherItem] = []
        var commandItems: [LauncherItem] = []
        for snapshot in snapshots {
            if Task.isCancelled { return [] }
            switch snapshot.searchMode {
            case .commandList:
                if trimmed.isEmpty {
                    items.append(contentsOf: LauncherSearchEngine.annotate(
                        items: snapshot.items,
                        query: trimmed,
                        records: records,
                        now: now,
                        aliasLookup: aliasLookup
                    ))
                } else {
                    commandItems.append(contentsOf: snapshot.items)
                }
            case .queryDriven:
                // Query-driven providers own their parsing semantics (for
                // example `f foo`, `menu Save`, expressions and translation).
                // Re-filtering with the raw launcher query creates false negatives.
                items.append(contentsOf: snapshot.items)
            }
        }
        if !trimmed.isEmpty {
            items.append(contentsOf: LauncherSearchEngine.annotate(
                items: commandItems,
                query: trimmed,
                records: records,
                now: now,
                aliasLookup: aliasLookup,
                limit: 200,
                preservingIDs: preservingIDs
            ))
        }
        return items
    }

    /// 按源模式产出条目:commandList 走引擎(模糊+拼音+frecency),
    /// queryDriven 原样传 query + 相关性兜底。
    static func process(
        sources: [LauncherItemSource],
        query: String,
        records: [String: CommandUsageRecord],
        now: Date = Date(),
        aliasLookup: (String) -> String? = { _ in nil },
        preservingIDs: Set<String> = []
    ) -> [LauncherItem] {
        process(
            snapshots: collect(sources: sources, query: query),
            query: query,
            records: records,
            now: now,
            aliasLookup: aliasLookup,
            preservingIDs: preservingIDs
        )
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
            items: process(
                sources: sources,
                query: query,
                records: records,
                preservingIDs: Set(favorites)
            ),
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
        let allItems = items.map { item -> LauncherItem in
            var copy = item
            copy.aliasBadge = aliasLookup(item.id)
            return copy
        }

        var sections: [LauncherSectionData] = []
        var seen = Set<String>()
        var seenApplicationTitles = Set<String>()
        let applicationCategories: Set<String> = ["App", "Application"]
        let applicationLikeCategories = applicationCategories.union(["系统设置", "System Settings"])

        func normalizedApplicationTitle(for item: LauncherItem) -> String? {
            guard applicationLikeCategories.contains(item.category) else { return nil }
            return item.title.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
        }

        func appendSection(_ id: LauncherSection, title: String, items: [LauncherItem]) {
            let fresh = items.filter { item in
                guard seen.insert(item.id).inserted else { return false }
                guard let normalizedTitle = normalizedApplicationTitle(for: item) else { return true }
                return seenApplicationTitles.insert(normalizedTitle).inserted
            }
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
            // 搜索:先全局排序,再按 Raycast 的信息层级拆出 Files 分区。
            let ranked = allItems.filter { !$0.isAnswer }
                .enumerated()
                .sorted { lhs, rhs in
                    let lhsTitle = normalizedApplicationTitle(for: lhs.element)
                    let rhsTitle = normalizedApplicationTitle(for: rhs.element)
                    if lhsTitle != nil, lhsTitle == rhsTitle {
                        let lhsIsApplication = applicationCategories.contains(lhs.element.category)
                        let rhsIsApplication = applicationCategories.contains(rhs.element.category)
                        if lhsIsApplication != rhsIsApplication {
                            return lhsIsApplication
                        }
                    }
                    if lhs.element.searchScore != rhs.element.searchScore {
                        return lhs.element.searchScore > rhs.element.searchScore
                    }
                    return lhs.offset < rhs.offset
                }
                .map(\.element)
            let files = ranked.filter { $0.category == "Files" }
            let results = ranked.filter { $0.category != "Files" }
            appendSection(.results("Results"), title: "Results", items: results)
            appendSection(.results("Files"), title: "Files", items: files)
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
