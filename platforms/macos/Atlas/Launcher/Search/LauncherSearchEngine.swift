import Foundation

/// Frecency: count × time decay (7-day half-life).
enum FrecencyRanker {
    static let halfLife: TimeInterval = 7 * 24 * 3600

    static func frecency(_ record: CommandUsageRecord?, now: Date = Date()) -> Double {
        guard let record else { return 0 }
        let age = max(0, now.timeIntervalSince(record.lastExecutedAt))
        let decay = exp(-log(2) * age / halfLife)
        return Double(record.executionCount) * decay
    }

    static func combined(matchScore: Int, frecency: Double) -> Double {
        let normalized = frecency / (frecency + 1)
        return Double(matchScore) * 0.7 + 100 * normalized * 0.3
    }
}

struct LauncherSearchDocument: Sendable {
    let id: String
    let ordinal: Int
    let title: PreparedSearchField
    let subtitle: PreparedSearchField?
    let alias: PreparedSearchField?
    let keywords: [PreparedSearchField]

    init(item: LauncherItem, ordinal: Int, alias: String? = nil) {
        id = item.id
        self.ordinal = ordinal
        title = PreparedSearchField(item.title)
        subtitle = Self.searchableSubtitle(item.subtitle, excluding: item.category)
            .map(PreparedSearchField.init)
        self.alias = alias.map(PreparedSearchField.init)
        keywords = item.keywords
            .filter { !Self.sameSearchText($0, item.category) }
            .map(PreparedSearchField.init)
    }

    /// Category is presentation/filter metadata, not a search field. Some
    /// legacy providers repeat it in subtitle (`Category · detail`) or keywords;
    /// remove only the standalone category segment and preserve useful detail.
    private static func searchableSubtitle(
        _ subtitle: String?,
        excluding category: String
    ) -> String? {
        guard let subtitle else { return nil }
        let components = subtitle
            .split(separator: "·", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !sameSearchText($0, category) }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: " · ")
    }

    private static func sameSearchText(_ lhs: String, _ rhs: String) -> Bool {
        let normalize: (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        return !normalize(rhs).isEmpty && normalize(lhs) == normalize(rhs)
    }
}

struct LauncherSearchHit: Sendable {
    let id: String
    let score: Double
    let titleHighlightOffsets: [Int]?
    let ordinal: Int
}

struct PreparedSearchField: Sendable {
    let text: String

    init(_ text: String) {
        self.text = text
    }
}

/// Swift facade for the Raycast-v2-style Rust search service.
///
/// File results come from the persistent catalog; transient launcher candidates
/// use the same Rust matcher without mutating that catalog.
enum RaycastV2Search {
    private static let fileIndexLock = NSLock()
    private static var fileIndexStarted = false

    static func startFileIndexIfNeeded() {
        fileIndexLock.lock()
        guard !fileIndexStarted else {
            fileIndexLock.unlock()
            return
        }
        fileIndexStarted = true
        fileIndexLock.unlock()

        let supportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Atlas/Search", isDirectory: true)
        guard let cachePath = supportDirectory?
            .appendingPathComponent("file-index-v3.bin", isDirectory: false)
            .path else {
            resetFileIndexStart()
            return
        }

        do {
            try fileIndexStart(
                roots: [FileManager.default.homeDirectoryForCurrentUser.path],
                cachePath: cachePath
            )
        } catch {
            resetFileIndexStart()
        }
    }

    static func searchFiles(query: String, limit: Int) -> [String] {
        startFileIndexIfNeeded()
        return (try? searchQuery(
            query: query,
            limit: UInt32(clamping: limit),
            namespaces: ["files"]
        ))?
        .map(\.path)
        .filter { !$0.hasSuffix(".app") } ?? []
    }

    static func rank(
        query: String,
        documents: [SearchDocumentInput],
        limit: Int
    ) -> [SearchResultEntry] {
        guard !documents.isEmpty else { return [] }
        return (try? searchRankDocuments(
            query: query,
            documents: documents,
            limit: UInt32(clamping: max(1, limit))
        )) ?? []
    }

    static func searchAliases(for text: String) -> [String] {
        var aliases: [String] = []
        let words = text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
        let initials = String(words.compactMap(\.first))
        if initials.count > 1 {
            aliases.append(initials)
        }
        let pinyin = PinyinIndexer.index(text)
        if pinyin.hasChinese {
            aliases.append(pinyin.full)
            aliases.append(pinyin.initials)
        }
        return aliases
    }

    private static func resetFileIndexStart() {
        fileIndexLock.lock()
        fileIndexStarted = false
        fileIndexLock.unlock()
    }
}

/// Pure launcher search engine. UI actions stay in LauncherItem; the matching
/// layer only receives Sendable value documents and returns lightweight hits.
enum LauncherSearchEngine {
    static func documents(
        for items: [LauncherItem],
        aliasLookup: (String) -> String? = { _ in nil }
    ) -> [LauncherSearchDocument] {
        items.enumerated().map {
            LauncherSearchDocument(item: $0.element, ordinal: $0.offset, alias: aliasLookup($0.element.id))
        }
    }

    static func search(
        documents: [LauncherSearchDocument],
        query: String,
        records: [String: CommandUsageRecord],
        now: Date = Date(),
        limit: Int? = nil,
        preservingIDs: Set<String> = []
    ) -> [LauncherSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedLimit = limit.map { max(1, $0) }
        if trimmed.isEmpty {
            var hits = documents.map { document in
                LauncherSearchHit(
                    id: document.id,
                    score: FrecencyRanker.frecency(records[document.id], now: now),
                    titleHighlightOffsets: nil,
                    ordinal: document.ordinal
                )
            }
            hits.sort(by: ranksBefore)
            return limited(hits, to: boundedLimit, preservingIDs: preservingIDs)
        }

        let byID = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        let ffiDocuments = documents.map(makeFFIDocument)
        let ranked = RaycastV2Search.rank(
            query: trimmed,
            documents: ffiDocuments,
            limit: min(documents.count, 50_000)
        )
        if Task.isCancelled { return [] }

        var hits = ranked.compactMap { result -> LauncherSearchHit? in
            guard let document = byID[result.id] else { return nil }
            var highlights = result.titleHighlightOffsets.map(Int.init)
            if highlights.isEmpty,
               !trimmed.contains(where: { $0.isWhitespace || "'^$!|".contains($0) }),
               let pinyinMatch = PinyinIndexer.bestMatch(query: trimmed, text: document.title.text) {
                highlights = pinyinMatch.positions
            }
            return LauncherSearchHit(
                id: document.id,
                score: FrecencyRanker.combined(
                    matchScore: Int(result.score),
                    frecency: FrecencyRanker.frecency(records[document.id], now: now)
                ),
                titleHighlightOffsets: highlights.isEmpty ? nil : highlights,
                ordinal: document.ordinal
            )
        }
        hits.sort(by: ranksBefore)
        return limited(hits, to: boundedLimit, preservingIDs: preservingIDs)
    }

    private static func makeFFIDocument(_ document: LauncherSearchDocument) -> SearchDocumentInput {
        var keywords = document.keywords.map(\.text)
        if let subtitle = document.subtitle {
            keywords.append(contentsOf: pinyinAliases(for: subtitle.text))
        }
        if let alias = document.alias {
            keywords.append(alias.text)
            keywords.append(contentsOf: pinyinAliases(for: alias.text))
        }
        keywords.append(contentsOf: pinyinAliases(for: document.title.text))
        for keyword in document.keywords {
            keywords.append(contentsOf: pinyinAliases(for: keyword.text))
        }
        return SearchDocumentInput(
            id: document.id,
            namespace: "launcher",
            title: document.title.text,
            subtitle: document.subtitle?.text ?? "",
            keywords: keywords,
            path: "",
            kind: "command",
            modifiedAt: 0
        )
    }

    private static func pinyinAliases(for text: String) -> [String] {
        RaycastV2Search.searchAliases(for: text)
    }

    private static func limited(
        _ hits: [LauncherSearchHit],
        to limit: Int?,
        preservingIDs: Set<String>
    ) -> [LauncherSearchHit] {
        guard let limit, hits.count > limit else { return hits }
        var result = Array(hits.prefix(limit))
        result.append(contentsOf: hits.dropFirst(limit).filter { preservingIDs.contains($0.id) })
        result.sort(by: ranksBefore)
        return result
    }

    /// Compatibility API used by existing source/builder tests.
    static func annotate(
        items: [LauncherItem],
        query: String,
        records: [String: CommandUsageRecord],
        now: Date = Date(),
        aliasLookup: (String) -> String? = { _ in nil },
        limit: Int? = nil,
        preservingIDs: Set<String> = []
    ) -> [LauncherItem] {
        let hits = search(
            documents: documents(for: items, aliasLookup: aliasLookup),
            query: query,
            records: records,
            now: now,
            limit: limit,
            preservingIDs: preservingIDs
        )
        let byID = Dictionary(grouping: items, by: \.id).compactMapValues(\.first)
        return hits.compactMap { hit in
            guard var item = byID[hit.id] else { return nil }
            item.searchScore = hit.score
            item.titleHighlightOffsets = hit.titleHighlightOffsets
            return item
        }
    }

    private static func ranksBefore(_ lhs: LauncherSearchHit, _ rhs: LauncherSearchHit) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.ordinal < rhs.ordinal
    }
}
