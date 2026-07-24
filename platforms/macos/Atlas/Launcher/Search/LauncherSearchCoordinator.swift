import Foundation

/// Search coordinator.
///
/// MainActor owns only observable state. Provider collection and ranking run in
/// cancellable background tasks; slow sources are debounced, concurrent and
/// incrementally merged under a query generation guard.
@MainActor
final class LauncherSearchCoordinator: ObservableObject {
    @Published private(set) var sections: [LauncherSectionData] = []
    @Published private(set) var loadingSources: Set<String> = []

    private let fastSources: [LauncherItemSource]
    private let slowSources: [LauncherItemSource]
    private let favorites: () -> [String]
    private let records: () -> [String: CommandUsageRecord]
    private let fallbackItems: (String) -> [LauncherItem]
    private let aliases: AliasResolving?
    private let aliasName: (String) -> String?

    private var generation = 0
    private var searchTask: Task<Void, Never>?
    private var currentQuery = ""
    private var currentFastItems: [LauncherItem] = []
    private var currentCandidateItems: [LauncherItem] = []
    private var slowResults: [String: [LauncherItem]] = [:]
    private var slowCandidates: [String: [LauncherItem]] = [:]
    private var currentFavorites: [String] = []
    private var currentRecords: [String: CommandUsageRecord] = [:]
    private var currentFallbackItems: [LauncherItem] = []

    init(
        sources: [LauncherItemSource],
        favorites: @escaping () -> [String],
        records: @escaping () -> [String: CommandUsageRecord],
        fallbackItems: @escaping (String) -> [LauncherItem],
        aliases: AliasResolving?,
        aliasName: @escaping (String) -> String?
    ) {
        fastSources = sources.filter { !$0.isSlow }
        slowSources = sources.filter { $0.isSlow }
        self.favorites = favorites
        self.records = records
        self.fallbackItems = fallbackItems
        self.aliases = aliases
        self.aliasName = aliasName
    }

    deinit {
        searchTask?.cancel()
    }

    func updateQuery(_ query: String) {
        let previousTrimmed = currentQuery.trimmingCharacters(in: .whitespaces)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        currentQuery = query
        generation += 1
        let activeGeneration = generation
        searchTask?.cancel()

        slowResults = [:]
        slowCandidates = [:]
        loadingSources = []
        // Preserve visible results while refining a non-empty query. Clearing the
        // published list here makes every keystroke render an empty frame before
        // the detached collector returns, which presents as panel flicker/jitter.
        if trimmed.isEmpty || previousTrimmed.isEmpty {
            currentFastItems = []
            currentCandidateItems = []
            sections = []
        }
        currentFavorites = favorites()
        currentRecords = records()
        currentFallbackItems = fallbackItems(trimmed)

        let sourceBox = UnsafeSendable(value: fastSources)
        let recordSnapshot = currentRecords

        searchTask = Task { [weak self] in
            guard let self else { return }

            let collectTask = Task.detached(priority: .userInitiated) {
                LauncherSectionBuilder.collect(sources: sourceBox.value, query: trimmed)
            }
            let snapshots = await withTaskCancellationHandler {
                await collectTask.value
            } onCancel: {
                collectTask.cancel()
            }
            guard !Task.isCancelled, self.generation == activeGeneration else { return }

            let candidates = snapshots.flatMap(\.items)
            var aliasSnapshot: [String: String] = [:]
            for item in candidates where aliasSnapshot[item.id] == nil {
                aliasSnapshot[item.id] = self.aliasName(item.id)
            }
            let snapshotBox = UnsafeSendable(value: snapshots)
            let pinnedIDs = Set(currentFavorites)

            let scoreTask = Task.detached(priority: .userInitiated) {
                LauncherSectionBuilder.process(
                    snapshots: snapshotBox.value,
                    query: trimmed,
                    records: recordSnapshot,
                    aliasLookup: { aliasSnapshot[$0] },
                    preservingIDs: pinnedIDs
                )
            }
            let fastItems = await withTaskCancellationHandler {
                await scoreTask.value
            } onCancel: {
                scoreTask.cancel()
            }
            guard !Task.isCancelled, self.generation == activeGeneration else { return }

            self.currentCandidateItems = candidates
            self.currentFastItems = fastItems
            self.publish(generation: activeGeneration)

            guard !trimmed.isEmpty, !self.slowSources.isEmpty else { return }
            self.loadingSources = Set(self.slowSources.map(\.sourceID))

            do {
                try await Task.sleep(nanoseconds: 60_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, self.generation == activeGeneration else { return }
            await self.runSlowSources(query: trimmed, generation: activeGeneration)
        }
    }

    private func runSlowSources(query: String, generation activeGeneration: Int) async {
        let sources = slowSources.map { UnsafeSendable(value: $0) }
        let recordSnapshot = currentRecords

        await withTaskGroup(of: SlowSourceResult?.self) { group in
            for sourceBox in sources {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let source = sourceBox.value
                    let raw: [LauncherItem]

                    if let asynchronous = source as? AsyncLauncherItemSource {
                        raw = await asynchronous.itemsAsync(for: query)
                    } else {
                        let work = Task.detached(priority: .utility) {
                            source.items(for: query)
                        }
                        raw = await withTaskCancellationHandler {
                            await work.value
                        } onCancel: {
                            work.cancel()
                        }
                    }
                    guard !Task.isCancelled else { return nil }

                    let snapshot = LauncherSourceSnapshot(
                        sourceID: source.sourceID,
                        searchMode: source.searchMode,
                        items: raw
                    )
                    let processed = LauncherSectionBuilder.process(
                        snapshots: [snapshot],
                        query: query,
                        records: recordSnapshot
                    )
                    return SlowSourceResult(
                        sourceID: source.sourceID,
                        candidates: raw,
                        items: processed
                    )
                }
            }

            for await result in group {
                guard let result,
                      !Task.isCancelled,
                      generation == activeGeneration else { continue }
                slowCandidates[result.sourceID] = result.candidates
                slowResults[result.sourceID] = result.items
                loadingSources.remove(result.sourceID)
                publish(generation: activeGeneration)
            }
        }
    }

    private func publish(generation activeGeneration: Int) {
        guard activeGeneration == generation else { return }
        let trimmed = currentQuery.trimmingCharacters(in: .whitespaces)
        let allItems = currentFastItems + slowResults.values.flatMap { $0 }
        let candidateItems = currentCandidateItems + slowCandidates.values.flatMap { $0 }

        sections = LauncherSectionBuilder.assemble(
            items: allItems,
            query: trimmed,
            aliasLookup: { [aliasName] key in aliasName(key) },
            resolveAliasItems: { [aliases] trimmedQuery in
                guard let aliases,
                      let key = aliases.commandKey(matching: trimmedQuery.lowercased()) else { return [] }
                return candidateItems.filter { $0.id == key }
            },
            favorites: currentFavorites,
            records: currentRecords,
            fallbackItems: currentFallbackItems
        )
    }
}

private struct SlowSourceResult: @unchecked Sendable {
    let sourceID: String
    let candidates: [LauncherItem]
    let items: [LauncherItem]
}
