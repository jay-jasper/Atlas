import XCTest
@testable import Atlas

@MainActor
final class ScratchpadStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScratchpadStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCreatePersistsMarkdownNote() throws {
        let store = makeStore(date: Date(timeIntervalSince1970: 10))

        let note = try store.create(ScratchpadDraft(title: "Plan", markdown: "# Heading\n- item"))
        let loaded = try makeStore().loadNotes()

        XCTAssertEqual(note.title, "Plan")
        XCTAssertEqual(note.markdown, "# Heading\n- item")
        XCTAssertEqual(loaded, [note])
    }

    func testCreateUsesFirstMarkdownLineWhenTitleIsEmpty() throws {
        let store = makeStore()

        let note = try store.create(ScratchpadDraft(title: "   ", markdown: "First line\nSecond line"))

        XCTAssertEqual(note.title, "First line")
    }

    func testRejectsEmptyDraft() {
        let store = makeStore()

        XCTAssertThrowsError(try store.create(ScratchpadDraft(title: " ", markdown: "\n"))) { error in
            XCTAssertEqual(error as? ScratchpadStoreError, .invalidDraft)
        }
    }

    func testUpdatePreservesCreatedAtAndChangesUpdatedAt() throws {
        let createdAt = Date(timeIntervalSince1970: 10)
        let updatedAt = Date(timeIntervalSince1970: 20)
        let store = makeStore(date: createdAt)
        let note = try store.create(ScratchpadDraft(title: "Draft", markdown: "Old"))

        let updateStore = makeStore(date: updatedAt)
        let updated = try updateStore.update(
            id: note.id,
            draft: ScratchpadDraft(title: "Final", markdown: "New **markdown**")
        )

        XCTAssertEqual(updated.id, note.id)
        XCTAssertEqual(updated.createdAt, createdAt)
        XCTAssertEqual(updated.updatedAt, updatedAt)
        XCTAssertEqual(updated.title, "Final")
        XCTAssertEqual(updated.markdown, "New **markdown**")
    }

    func testDeleteRemovesNote() throws {
        let store = makeStore()
        let note = try store.create(ScratchpadDraft(title: "Delete me", markdown: "body"))

        try store.delete(id: note.id)

        XCTAssertEqual(try store.loadNotes(), [])
    }

    func testSearchMatchesTitleAndMarkdown() throws {
        let store = makeStore()
        _ = try store.create(ScratchpadDraft(title: "Release", markdown: "Ship checklist"))
        _ = try store.create(ScratchpadDraft(title: "Idea", markdown: "Markdown parser notes"))

        XCTAssertEqual(try store.search("release").map(\.title), ["Release"])
        XCTAssertEqual(try store.search("parser").map(\.title), ["Idea"])
    }

    func testInvalidJsonThrowsDecodeError() throws {
        let fileURL = notesURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        XCTAssertThrowsError(try makeStore().loadNotes())
    }

    private func makeStore(date: Date = Date(timeIntervalSince1970: 1)) -> ScratchpadStore {
        ScratchpadStore(fileURL: notesURL(), dateProvider: { date })
    }

    private func notesURL() -> URL {
        tempDirectory.appendingPathComponent("notes.json")
    }
}
