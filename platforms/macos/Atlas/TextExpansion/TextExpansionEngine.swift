import Foundation

struct TextSnippet: Codable, Equatable, Identifiable {
    var id: UUID
    var trigger: String
    var expansion: String

    init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }

    var isValid: Bool {
        !trigger.trimmingCharacters(in: .whitespaces).isEmpty &&
        !expansion.isEmpty
    }
}

/// Pure trigger-matching engine. Given a recently-typed buffer and the snippet
/// table, determines whether the tail of the buffer matches a trigger and, if
/// so, how many characters to delete and what to insert. Dynamic placeholders
/// `{date}` / `{time}` are expanded relative to an injected clock.
enum TextExpansionEngine {
    struct Match: Equatable {
        let deleteCount: Int
        let insertText: String
    }

    /// Returns the expansion for the longest trigger that is a suffix of `buffer`.
    static func match(buffer: String, snippets: [TextSnippet], now: Date = Date()) -> Match? {
        let candidates = snippets
            .filter { $0.isValid && buffer.hasSuffix($0.trigger) }
            .sorted { $0.trigger.count > $1.trigger.count }
        guard let snippet = candidates.first else { return nil }
        return Match(
            deleteCount: snippet.trigger.count,
            insertText: expandPlaceholders(snippet.expansion, now: now)
        )
    }

    static func expandPlaceholders(_ text: String, now: Date) -> String {
        guard text.contains("{") else { return text }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        return text
            .replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))
            .replacingOccurrences(of: "{time}", with: timeFormatter.string(from: now))
    }
}
