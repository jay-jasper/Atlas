import Foundation

/// Frecency:次数 × 时间衰减(半衰期 7 天)。
enum FrecencyRanker {
    static let halfLife: TimeInterval = 7 * 24 * 3600

    static func frecency(_ record: CommandUsageRecord?, now: Date = Date()) -> Double {
        guard let record else { return 0 }
        let age = max(0, now.timeIntervalSince(record.lastExecutedAt))
        let decay = exp(-log(2) * age / halfLife)
        return Double(record.executionCount) * decay
    }

    /// 综合分:匹配 ×0.7 + 归一化 frecency ×0.3(压到与匹配同量级)。
    static func combined(matchScore: Int, frecency: Double) -> Double {
        let normalized = frecency / (frecency + 1)
        return Double(matchScore) * 0.7 + 100 * normalized * 0.3
    }
}

/// 搜索引擎:对 commandList 源的条目做 模糊+拼音 匹配、frecency 合分、
/// 标注高亮位置,输出已过滤排序的条目副本。
enum LauncherSearchEngine {
    static func annotate(
        items: [LauncherItem],
        query: String,
        records: [String: CommandUsageRecord],
        now: Date = Date()
    ) -> [LauncherItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            // 空查询:全量返回,按 frecency 排(供收藏/最近/分区用)。
            return items
                .map { item -> LauncherItem in
                    var copy = item
                    copy.searchScore = FrecencyRanker.frecency(records[item.id], now: now)
                    copy.titleHighlightOffsets = nil
                    return copy
                }
                .sorted { $0.searchScore > $1.searchScore }
        }

        var scored: [LauncherItem] = []
        for item in items {
            var bestScore: Int?
            var highlights: [Int]?

            if let titleMatch = PinyinIndexer.bestMatch(query: trimmed, text: item.title) {
                bestScore = titleMatch.score
                highlights = titleMatch.positions
            }

            // 关键词命中打八折,不高亮标题。
            for keyword in item.keywords {
                if let kw = PinyinIndexer.bestMatch(query: trimmed, text: keyword) {
                    let discounted = Int(Double(kw.score) * 0.8)
                    if bestScore == nil || discounted > bestScore! {
                        bestScore = discounted
                        highlights = nil
                    }
                }
            }

            guard let matchScore = bestScore else { continue }
            var copy = item
            copy.searchScore = FrecencyRanker.combined(
                matchScore: matchScore,
                frecency: FrecencyRanker.frecency(records[item.id], now: now)
            )
            copy.titleHighlightOffsets = highlights
            scored.append(copy)
        }
        return scored.sorted { $0.searchScore > $1.searchScore }
    }
}
