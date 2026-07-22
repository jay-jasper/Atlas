import Foundation

struct LauncherSectionData: Identifiable {
    let id: LauncherSection
    let title: String
    let items: [LauncherItem]
}

enum LauncherSectionBuilder {
    static func build(
        query: String,
        sources: [LauncherItemSource],
        favorites: [String],
        records: [String: CommandUsageRecord],
        fallbackItems: [LauncherItem] = [],
        aliases: AliasResolving? = nil,
        recentsLimit: Int = 5
    ) -> [LauncherSectionData] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let allItems = sources.flatMap { $0.items(for: trimmed) }

        var sections: [LauncherSectionData] = []
        var seen = Set<String>()

        func appendSection(_ id: LauncherSection, title: String, items: [LauncherItem]) {
            let fresh = items.filter { seen.insert($0.id).inserted }
            guard !fresh.isEmpty else { return }
            sections.append(LauncherSectionData(id: id, title: title, items: fresh))
        }

        // Alias exact/prefix hit resolves the aliased command to the very top.
        var aliasItems: [LauncherItem] = []
        if !trimmed.isEmpty,
           let aliases,
           let aliasedKey = aliases.commandKey(matching: trimmed.lowercased()) {
            let rootItems = sources.flatMap { $0.items(for: "") }
            aliasItems = rootItems.filter { $0.id == aliasedKey }
        }

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

        // Per-category result sections, ranked by usage inside each category.
        let grouped = Dictionary(grouping: allItems.filter { !$0.isAnswer }, by: \.category)
        let categoryOrder = allItems.map(\.category).uniqued()
        for category in categoryOrder {
            guard let items = grouped[category] else { continue }
            let ranked = rankByUsage(items, records: records)
            appendSection(.results(category), title: category, items: ranked)
        }

        if !trimmed.isEmpty, !fallbackItems.isEmpty {
            appendSection(.fallback, title: "Use \"\(trimmed)\" with…", items: fallbackItems)
        }

        return sections
    }

    private static func rankByUsage(
        _ items: [LauncherItem],
        records: [String: CommandUsageRecord]
    ) -> [LauncherItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                let lhsRecord = records[lhs.element.id]
                let rhsRecord = records[rhs.element.id]
                let lhsCount = lhsRecord?.executionCount ?? 0
                let rhsCount = rhsRecord?.executionCount ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                let lhsDate = lhsRecord?.lastExecutedAt ?? .distantPast
                let rhsDate = rhsRecord?.lastExecutedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
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
