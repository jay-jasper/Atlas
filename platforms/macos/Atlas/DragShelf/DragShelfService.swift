import Foundation

@MainActor
final class DragShelfService: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var statusMessage = ""

    private var shelf = DragShelf()
    private let ops: ShelfFileOperating

    init(ops: ShelfFileOperating = LiveShelfFileOps()) {
        self.ops = ops
    }

    func add(urls: [URL]) {
        shelf.add(contentsOf: urls)
        items = shelf.items
    }

    func remove(id: UUID) {
        shelf.remove(id: id)
        items = shelf.items
    }

    func clear() {
        shelf.clear()
        items = shelf.items
        statusMessage = ""
    }

    func copyAll(to destination: URL) {
        let failures = shelf.copyAll(to: destination, using: ops)
        if failures.isEmpty {
            statusMessage = "Copied \(items.count) item\(items.count == 1 ? "" : "s")."
        } else {
            statusMessage = "\(failures.count) item(s) could not be copied."
        }
    }
}
