import Foundation

protocol ScratchpadStoring {
    func loadNotes() throws -> [ScratchpadNote]
    func create(_ draft: ScratchpadDraft) throws -> ScratchpadNote
    func update(id: UUID, draft: ScratchpadDraft) throws -> ScratchpadNote
    func delete(id: UUID) throws
    func search(_ query: String) throws -> [ScratchpadNote]
}

final class ScratchpadStore: ScratchpadStoring {
    private let fileURL: URL
    private let dateProvider: () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL = ScratchpadStore.defaultFileURL(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.dateProvider = dateProvider
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadNotes() throws -> [ScratchpadNote] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([ScratchpadNote].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func create(_ draft: ScratchpadDraft) throws -> ScratchpadNote {
        guard draft.isValid else { throw ScratchpadStoreError.invalidDraft }
        let now = dateProvider()
        let note = ScratchpadNote(
            title: title(for: draft),
            markdown: draft.markdown,
            createdAt: now,
            updatedAt: now
        )
        var notes = try loadNotes()
        notes.insert(note, at: 0)
        try save(notes)
        return note
    }

    func update(id: UUID, draft: ScratchpadDraft) throws -> ScratchpadNote {
        guard draft.isValid else { throw ScratchpadStoreError.invalidDraft }
        var notes = try loadNotes()
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw ScratchpadStoreError.noteNotFound
        }

        let existing = notes[index]
        let updated = ScratchpadNote(
            id: existing.id,
            title: title(for: draft),
            markdown: draft.markdown,
            createdAt: existing.createdAt,
            updatedAt: dateProvider()
        )
        notes[index] = updated
        try save(notes)
        return updated
    }

    func delete(id: UUID) throws {
        var notes = try loadNotes()
        let originalCount = notes.count
        notes.removeAll { $0.id == id }
        guard notes.count != originalCount else {
            throw ScratchpadStoreError.noteNotFound
        }
        try save(notes)
    }

    func search(_ query: String) throws -> [ScratchpadNote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return try loadNotes() }
        return try loadNotes().filter { note in
            note.title.localizedCaseInsensitiveContains(q) ||
                note.markdown.localizedCaseInsensitiveContains(q)
        }
    }

    private func save(_ notes: [ScratchpadNote]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(notes.sorted { $0.updatedAt > $1.updatedAt })
        try data.write(to: fileURL, options: [.atomic])
    }

    private func title(for draft: ScratchpadDraft) -> String {
        if !draft.normalizedTitle.isEmpty {
            return draft.normalizedTitle
        }

        return draft.normalizedMarkdown
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0.prefix(80)) } ?? "Untitled"
    }

    static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("Scratchpad", isDirectory: true)
            .appendingPathComponent("notes.json")
    }
}
