import XCTest
@testable import Atlas

final class FlowInboxStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowInboxStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadFavoritesReturnsEmptyWhenFileAbsent() {
        XCTAssertEqual(makeStore().loadFavorites(), [])
    }

    func testAddFavoritePersistsAndLoads() {
        let store = makeStore()
        store.addFavorite(title: "Hello", body: "World", source: "test")
        let favorites = store.loadFavorites()
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites[0].title, "Hello")
        XCTAssertEqual(favorites[0].body, "World")
        XCTAssertEqual(favorites[0].source, "test")
    }

    func testRemoveFavoriteByID() {
        let store = makeStore()
        store.addFavorite(title: "Keep", body: "", source: "a")
        store.addFavorite(title: "Remove", body: "", source: "b")
        let removeID = store.loadFavorites().first(where: { $0.title == "Remove" })!.id
        store.removeFavorite(id: removeID)
        XCTAssertFalse(store.loadFavorites().contains { $0.id == removeID })
        XCTAssertTrue(store.loadFavorites().contains { $0.title == "Keep" })
    }

    func testAddFileDeduplicatesByPath() throws {
        let store = makeStore()
        let file = tempDir.appendingPathComponent("doc.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        store.addFile(url: file)
        store.addFile(url: file)
        XCTAssertEqual(store.loadFiles().count, 1)
    }

    func testLoadFilesFiltersNonexistentPaths() {
        let store = makeStore()
        let ghost = tempDir.appendingPathComponent("ghost.txt")
        store.addFile(url: ghost)
        XCTAssertEqual(store.loadFiles().count, 0)
    }

    func testRemoveFileByID() throws {
        let store = makeStore()
        let file = tempDir.appendingPathComponent("keep.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        store.addFile(url: file)
        let id = store.loadFiles().first!.id
        store.removeFile(id: id)
        XCTAssertEqual(store.loadFiles().count, 0)
    }

    func testBuildItemsIncludesFavoritesAndFiles() throws {
        let store = makeStore()
        store.addFavorite(title: "Fav", body: "text", source: "clip")
        let file = tempDir.appendingPathComponent("note.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        store.addFile(url: file)

        let items = store.buildItems(clipboardStore: StubClipboardStore(), screenshotStore: ScreenshotLibraryStore(rootDirectory: tempDir))
        XCTAssertTrue(items.contains { $0.kind == .favorite })
        XCTAssertTrue(items.contains { $0.kind == .file })
    }

    private func makeStore() -> FlowInboxStore {
        FlowInboxStore(url: tempDir.appendingPathComponent("inbox.json"))
    }
}

private final class StubClipboardStore: ClipboardHistoryStoring {
    func items() -> [ClipboardHistoryItem] { [] }
    func search(_ query: String) -> [ClipboardHistoryItem] { [] }
    func addText(_ text: String, capturedAt: Date) {}
    func addImageMetadata(_ metadata: ClipboardImageMetadata, capturedAt: Date) {}
    func delete(id: UUID) {}
    func clear() {}
}
