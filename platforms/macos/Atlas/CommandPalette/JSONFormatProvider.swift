import Foundation

/// Formats/validates JSON. Triggers when the query starts with `{`/`[` or the
/// `json ` keyword. Pretty-prints with 2-space indentation and sorted keys, or
/// reports invalid JSON. Copies the formatted output on selection.
final class JSONFormatProvider: CommandProviding {
    private let copy: PasteboardWriting

    init(copy: @escaping PasteboardWriting = Pasteboard.system) {
        self.copy = copy
    }

    func results(for query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if trimmed.lowercased().hasPrefix("json ") {
            candidate = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            candidate = trimmed
        } else {
            return []
        }

        guard let data = candidate.data(using: .utf8) else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return [PaletteCommand(
                id: UUID(),
                title: "Invalid JSON",
                subtitle: "Input is not well-formed JSON",
                icon: .sfSymbol("exclamationmark.triangle"),
                keywords: ["json", "format", "validate"],
                action: .execute {},
                category: "JSON"
            )]
        }

        guard let pretty = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let formatted = String(data: pretty, encoding: .utf8) else {
            return []
        }

        return [PaletteCommand(
            id: UUID(),
            title: "Format JSON",
            subtitle: "Valid · \(formatted.count) chars · ↵ to copy formatted",
            icon: .sfSymbol("curlybraces"),
            keywords: ["json", "format", "pretty", "validate"],
            action: .execute { [copy] in copy(formatted) },
            category: "JSON"
        )]
    }
}
