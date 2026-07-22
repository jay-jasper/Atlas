import Foundation

/// 搜索总控:快源同步直出,慢源防抖后台跑,generation 丢弃过期结果。
/// 输入线程零阻塞;每个慢源有独立 loading 状态。
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
    private var slowResults: [String: [LauncherItem]] = [:]
    private var debounceTask: Task<Void, Never>?
    private var currentQuery = ""

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

    func updateQuery(_ query: String) {
        currentQuery = query
        generation += 1
        let gen = generation

        // 快源同步直出。
        rebuild(gen: gen)

        // 慢源防抖后台。
        debounceTask?.cancel()
        guard !slowSources.isEmpty else { return }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            slowResults = [:]
            loadingSources = []
            return
        }
        let slowList = slowSources
        loadingSources = Set(slowList.map(\.sourceID))
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            for source in slowList {
                guard self.generation == gen else { return }
                let records = self.records()
                // 慢源逐个执行(items(for:) 为 MainActor 接口;await 让出主线程,
                // 输入不被长任务卡死 —— 真正的重活在 provider 内部自行分线程)。
                let items = LauncherSectionBuilder.process(
                    sources: [source], query: trimmed, records: records
                )
                await Task.yield()
                guard self.generation == gen else { return }
                self.slowResults[source.sourceID] = items
                self.loadingSources.remove(source.sourceID)
                self.rebuild(gen: gen)
            }
        }
    }

    private func rebuild(gen: Int) {
        guard gen == generation else { return }
        let trimmed = currentQuery.trimmingCharacters(in: .whitespaces)
        let fastItems = LauncherSectionBuilder.process(
            sources: fastSources,
            query: trimmed,
            records: records()
        )
        let slowItems = trimmed.isEmpty ? [] : slowResults.values.flatMap { $0 }
        sections = LauncherSectionBuilder.assemble(
            items: fastItems + slowItems,
            query: trimmed,
            aliasLookup: { [aliasName] key in aliasName(key) },
            resolveAliasItems: { [fastSources, aliases] trimmedQuery in
                guard let aliases,
                      let key = aliases.commandKey(matching: trimmedQuery.lowercased()) else { return [] }
                return fastSources.flatMap { $0.items(for: "") }.filter { $0.id == key }
            },
            favorites: favorites(),
            records: records(),
            fallbackItems: fallbackItems(trimmed)
        )
    }
}
