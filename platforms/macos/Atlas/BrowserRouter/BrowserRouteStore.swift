import Foundation

protocol BrowserRouteStoring {
    func routes() -> [BrowserRoute]
    func save(_ routes: [BrowserRoute]) throws
    func upsert(_ route: BrowserRoute) throws
    func delete(id: UUID) throws
}

final class BrowserRouteStore: BrowserRouteStoring {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = BrowserRouteStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func routes() -> [BrowserRoute] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([BrowserRoute].self, from: data)) ?? []
    }

    func save(_ routes: [BrowserRoute]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(routes).write(to: fileURL, options: [.atomic])
    }

    func upsert(_ route: BrowserRoute) throws {
        var current = routes()
        if let index = current.firstIndex(where: { $0.id == route.id }) {
            current[index] = route
        } else {
            current.append(route)
        }
        try save(current)
    }

    func delete(id: UUID) throws {
        try save(routes().filter { $0.id != id })
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("browser-routes.json")
    }
}

final class InMemoryBrowserRouteStore: BrowserRouteStoring {
    private var store: [BrowserRoute]
    init(routes: [BrowserRoute] = []) { store = routes }
    func routes() -> [BrowserRoute] { store }
    func save(_ routes: [BrowserRoute]) throws { store = routes }
    func upsert(_ route: BrowserRoute) throws {
        if let i = store.firstIndex(where: { $0.id == route.id }) { store[i] = route } else { store.append(route) }
    }
    func delete(id: UUID) throws { store.removeAll { $0.id == id } }
}
