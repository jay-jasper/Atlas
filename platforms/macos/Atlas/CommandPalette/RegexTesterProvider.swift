import Foundation

/// Tests a regular expression: `regex /pattern/ on <text>`. Shows the number of
/// matches and the first match's capture groups. Copies the first match on select.
final class RegexTesterProvider: CommandProviding {
    private let copy: PasteboardWriting

    init(copy: @escaping PasteboardWriting = Pasteboard.system) {
        self.copy = copy
    }

    func results(for query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("regex ") else { return [] }
        guard let parsed = Self.parse(String(trimmed.dropFirst(6))) else { return [] }

        guard let regex = try? NSRegularExpression(pattern: parsed.pattern) else {
            return [PaletteCommand(
                id: UUID(),
                title: "Invalid regex",
                subtitle: "Pattern /\(parsed.pattern)/ does not compile",
                icon: .sfSymbol("exclamationmark.triangle"),
                keywords: ["regex", "regular expression"],
                action: .execute {},
                category: "Regex"
            )]
        }

        let text = parsed.text
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard let first = matches.first, let firstRange = Range(first.range, in: text) else {
            return [PaletteCommand(
                id: UUID(),
                title: "No matches",
                subtitle: "/\(parsed.pattern)/ on \"\(text)\"",
                icon: .sfSymbol("magnifyingglass"),
                keywords: ["regex"],
                action: .execute {},
                category: "Regex"
            )]
        }

        let firstMatch = String(text[firstRange])
        var groups: [String] = []
        for i in 1..<first.numberOfRanges {
            if let r = Range(first.range(at: i), in: text) {
                groups.append(String(text[r]))
            }
        }
        let groupInfo = groups.isEmpty ? "" : " · groups: \(groups.joined(separator: ", "))"

        return [PaletteCommand(
            id: UUID(),
            title: "\(matches.count) match\(matches.count == 1 ? "" : "es") — first: \"\(firstMatch)\"",
            subtitle: "/\(parsed.pattern)/\(groupInfo) · ↵ to copy first match",
            icon: .sfSymbol("magnifyingglass"),
            keywords: ["regex", "match", "pattern"],
            action: .execute { [copy] in copy(firstMatch) },
            category: "Regex"
        )]
    }

    /// Parses `/pattern/ on text` into pattern and text.
    static func parse(_ input: String) -> (pattern: String, text: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }
        let afterSlash = trimmed.dropFirst()
        guard let closeIndex = afterSlash.firstIndex(of: "/") else { return nil }
        let pattern = String(afterSlash[afterSlash.startIndex..<closeIndex])
        var rest = String(afterSlash[afterSlash.index(after: closeIndex)...]).trimmingCharacters(in: .whitespaces)
        if rest.lowercased().hasPrefix("on ") {
            rest = String(rest.dropFirst(3))
        }
        guard !pattern.isEmpty, !rest.isEmpty else { return nil }
        return (pattern, rest.trimmingCharacters(in: .whitespaces))
    }
}
