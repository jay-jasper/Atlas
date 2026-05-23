import Foundation

final class SnippetsProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let snippetProvider: SnippetProviding
    private let clipboard: ClipboardReading
    private let accessLogger: PrivacyPulseAccessLogging

    init(
        snippetProvider: SnippetProviding = SnippetStore(),
        clipboard: ClipboardReading = SystemClipboardReader(),
        accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
    ) {
        self.snippetProvider = snippetProvider
        self.clipboard = clipboard
        self.accessLogger = accessLogger
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return snippetProvider.snippets()
            .filter { snippet in
                snippet.title.localizedCaseInsensitiveContains(q) ||
                    snippet.body.localizedCaseInsensitiveContains(q) ||
                    snippet.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
            }
            .prefix(Self.maxResultsCount)
            .map { [clipboard, accessLogger] snippet in
                PaletteCommand(
                    id: UUID(),
                    title: "Copy \(snippet.title)",
                    subtitle: Self.subtitle(for: snippet.body),
                    icon: .sfSymbol("text.quote"),
                    keywords: snippet.keywords + [snippet.title],
                    action: .execute {
                        accessLogger.record(
                            category: .clipboard,
                            title: "Clipboard Write",
                            detail: "Snippet copied text to the pasteboard"
                        )
                        clipboard.setString(snippet.body)
                    },
                    category: "Snippet"
                )
            }
    }

    private static func subtitle(for body: String) -> String {
        let collapsedBody = body
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return String(collapsedBody.prefix(80))
    }
}
