import XCTest
@testable import Atlas

final class ScratchpadProviderTests: XCTestCase {
    func testReturnsNoResultsWhenDisabled() {
        let store = InMemoryScratchpadStore(notes: [
            ScratchpadNote(title: "Release", markdown: "Ship checklist"),
        ])
        let provider = ScratchpadProvider(store: store, isEnabled: false)

        XCTAssertEqual(provider.results(for: "release").count, 0)
    }

    func testReturnsOpenCommandForEmptyQueryWhenEnabled() {
        let provider = ScratchpadProvider(store: InMemoryScratchpadStore(), isEnabled: true)

        let results = provider.results(for: " ")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Open Scratchpad")
        XCTAssertEqual(results[0].category, "Scratchpad")
        guard case .push(let destination) = results[0].action else {
            return XCTFail("Expected push action")
        }
        guard case .scratchpad(let noteID) = destination else {
            return XCTFail("Expected scratchpad destination")
        }
        XCTAssertNil(noteID)
    }

    func testSearchesNotesWhenEnabled() {
        let matching = ScratchpadNote(title: "Release", markdown: "Ship checklist")
        let other = ScratchpadNote(title: "Ideas", markdown: "Later")
        let provider = ScratchpadProvider(
            store: InMemoryScratchpadStore(notes: [matching, other]),
            isEnabled: true
        )

        let results = provider.results(for: "ship")

        XCTAssertEqual(results.map(\.title), ["Release"])
        XCTAssertEqual(results.first?.category, "Scratchpad")
        guard let action = results.first?.action,
              case .push(let destination) = action else {
            return XCTFail("Expected push action")
        }
        guard case .scratchpad(let noteID) = destination else {
            return XCTFail("Expected scratchpad destination")
        }
        XCTAssertEqual(noteID, matching.id)
    }

    func testSetEnabledAllowsResults() {
        let provider = ScratchpadProvider(
            store: InMemoryScratchpadStore(notes: [
                ScratchpadNote(title: "Daily", markdown: "Notes"),
            ]),
            isEnabled: false
        )

        provider.setEnabled(true)

        XCTAssertEqual(provider.results(for: "daily").map(\.title), ["Daily"])
    }
}

private final class InMemoryScratchpadStore: ScratchpadStoring {
    private var notes: [ScratchpadNote]

    init(notes: [ScratchpadNote] = []) {
        self.notes = notes
    }

    func loadNotes() throws -> [ScratchpadNote] {
        notes
    }

    func create(_ draft: ScratchpadDraft) throws -> ScratchpadNote {
        let note = ScratchpadNote(title: draft.normalizedTitle, markdown: draft.markdown)
        notes.insert(note, at: 0)
        return note
    }

    func update(id: UUID, draft: ScratchpadDraft) throws -> ScratchpadNote {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw ScratchpadStoreError.noteNotFound
        }
        let updated = ScratchpadNote(
            id: id,
            title: draft.normalizedTitle,
            markdown: draft.markdown,
            createdAt: notes[index].createdAt,
            updatedAt: Date()
        )
        notes[index] = updated
        return updated
    }

    func delete(id: UUID) throws {
        notes.removeAll { $0.id == id }
    }

    func search(_ query: String) throws -> [ScratchpadNote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
                $0.markdown.localizedCaseInsensitiveContains(q)
        }
    }
}
