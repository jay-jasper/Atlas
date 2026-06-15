import Foundation

struct FeedSubscription: Codable, Equatable, Identifiable {
    var id: UUID
    var url: String
    var title: String

    init(id: UUID = UUID(), url: String, title: String) {
        self.id = id
        self.url = url
        self.title = title
    }
}

protocol FeedFetching {
    func fetch(_ url: URL) async -> Data?
}

struct URLSessionFeedFetcher: FeedFetching {
    func fetch(_ url: URL) async -> Data? {
        (try? await URLSession.shared.data(from: url))?.0
    }
}

protocol RSSStoring {
    func subscriptions() -> [FeedSubscription]
    func save(_ subscriptions: [FeedSubscription]) throws
}

final class RSSStore: RSSStoring {
    private let fileURL: URL
    init(fileURL: URL = RSSStore.defaultFileURL()) { self.fileURL = fileURL }

    func subscriptions() -> [FeedSubscription] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([FeedSubscription].self, from: data)) ?? []
    }
    func save(_ subscriptions: [FeedSubscription]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(subscriptions).write(to: fileURL, options: [.atomic])
    }
    static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("rss-feeds.json")
    }
}

final class InMemoryRSSStore: RSSStoring {
    private var store: [FeedSubscription]
    init(subscriptions: [FeedSubscription] = []) { store = subscriptions }
    func subscriptions() -> [FeedSubscription] { store }
    func save(_ subscriptions: [FeedSubscription]) throws { store = subscriptions }
}

@MainActor
final class RSSService: ObservableObject {
    @Published private(set) var subscriptions: [FeedSubscription] = []
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false

    private let store: RSSStoring
    private let fetcher: FeedFetching

    init(store: RSSStoring = RSSStore(), fetcher: FeedFetching = URLSessionFeedFetcher()) {
        self.store = store
        self.fetcher = fetcher
        subscriptions = store.subscriptions()
    }

    func addFeed(url: String) async {
        guard let parsed = await load(url: url) else { return }
        var updated = subscriptions
        updated.append(FeedSubscription(url: url, title: parsed.title.isEmpty ? url : parsed.title))
        try? store.save(updated)
        subscriptions = updated
    }

    func delete(id: UUID) {
        let updated = subscriptions.filter { $0.id != id }
        try? store.save(updated)
        subscriptions = updated
    }

    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }
        var collected: [FeedItem] = []
        for subscription in subscriptions {
            if let parsed = await load(url: subscription.url) {
                collected.append(contentsOf: parsed.items)
            }
        }
        items = collected
    }

    private func load(url urlString: String) async -> ParsedFeed? {
        guard let url = URL(string: urlString), let data = await fetcher.fetch(url) else { return nil }
        return FeedParser.parse(data)
    }
}
