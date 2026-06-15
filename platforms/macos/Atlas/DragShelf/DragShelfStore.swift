import Foundation

struct ShelfItem: Equatable, Identifiable {
    let id: UUID
    let url: URL
    var name: String { url.lastPathComponent }

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }
}

/// Operations the shelf performs on the filesystem, injected for testing.
protocol ShelfFileOperating {
    func copy(_ source: URL, to destinationDirectory: URL) throws
    func exists(_ url: URL) -> Bool
}

struct LiveShelfFileOps: ShelfFileOperating {
    private let fileManager = FileManager.default
    func copy(_ source: URL, to destinationDirectory: URL) throws {
        let dest = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        try fileManager.copyItem(at: source, to: dest)
    }
    func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }
}

/// Pure staging model for an edge-drop file shelf. Dedupes by path, supports
/// add/remove/clear, and batch-copy to a destination via injected file ops.
struct DragShelf: Equatable {
    private(set) var items: [ShelfItem] = []

    mutating func add(_ url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(ShelfItem(url: url))
    }

    mutating func add(contentsOf urls: [URL]) {
        urls.forEach { add($0) }
    }

    mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    mutating func clear() {
        items.removeAll()
    }

    /// Copies every staged item into `destination`. Returns the URLs that failed.
    func copyAll(to destination: URL, using ops: ShelfFileOperating) -> [URL] {
        var failures: [URL] = []
        for item in items {
            do {
                try ops.copy(item.url, to: destination)
            } catch {
                failures.append(item.url)
            }
        }
        return failures
    }
}
