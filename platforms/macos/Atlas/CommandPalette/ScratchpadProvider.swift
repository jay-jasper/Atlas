import Foundation

final class ScratchpadProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let store: ScratchpadStoring
    private var isEnabled: Bool

    init(store: ScratchpadStoring = ScratchpadStore(), isEnabled: Bool = false) {
        self.store = store
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled else { return [] }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return [
                PaletteCommand(
                    id: UUID(),
                    title: "Open Scratchpad",
                    subtitle: "Create and edit Markdown notes",
                    icon: .sfSymbol("note.text"),
                    keywords: ["scratchpad", "note", "markdown"],
                    action: .push(.scratchpad(noteID: nil)),
                    category: "Scratchpad"
                ),
            ]
        }

        let notes = (try? store.search(q)) ?? []
        return notes
            .prefix(Self.maxResultsCount)
            .map { note in
                PaletteCommand(
                    id: note.id,
                    title: note.title,
                    subtitle: Self.subtitle(for: note.markdown),
                    icon: .sfSymbol("note.text"),
                    keywords: ["scratchpad", "note", "markdown", note.title],
                    action: .push(.scratchpad(noteID: note.id)),
                    category: "Scratchpad"
                )
            }
    }

    private static func subtitle(for markdown: String) -> String {
        let collapsed = markdown
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return String(collapsed.prefix(80))
    }
}
