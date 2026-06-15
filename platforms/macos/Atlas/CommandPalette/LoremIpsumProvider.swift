import Foundation

/// Generates placeholder text: `lorem [N][p|s|w]` — N paragraphs (`p`),
/// sentences (`s`), or words (`w`). Defaults to 1 paragraph. Copies on select.
final class LoremIpsumProvider: CommandProviding {
    private let copy: PasteboardWriting

    init(copy: @escaping PasteboardWriting = Pasteboard.system) {
        self.copy = copy
    }

    private static let words = """
    lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor \
    incididunt ut labore et dolore magna aliqua enim ad minim veniam quis nostrud \
    exercitation ullamco laboris nisi aliquip ex ea commodo consequat duis aute \
    irure in reprehenderit voluptate velit esse cillum eu fugiat nulla pariatur
    """.split(separator: " ").map(String.init)

    enum Unit { case paragraphs, sentences, words }

    func results(for query: String) -> [PaletteCommand] {
        let parts = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard let keyword = parts.first, keyword == "lorem" || keyword == "ipsum" else { return [] }

        var count = 1
        var unit: Unit = .paragraphs
        if parts.count > 1 {
            let (n, u) = Self.parseSpec(parts[1])
            count = min(max(n, 1), 50)
            unit = u
        }

        let value = generate(count: count, unit: unit)
        let unitLabel: String
        switch unit {
        case .paragraphs: unitLabel = "paragraph"
        case .sentences: unitLabel = "sentence"
        case .words: unitLabel = "word"
        }
        let preview = String(value.prefix(60))
        let ellipsis = value.count > 60 ? "…" : ""
        let subtitle = "\(preview)\(ellipsis) · ↵ to copy"
        return [PaletteCommand(
            id: UUID(),
            title: "Lorem ipsum — \(count) \(unitLabel)\(count == 1 ? "" : "s")",
            subtitle: subtitle,
            icon: .sfSymbol("text.alignleft"),
            keywords: ["lorem", "ipsum", "placeholder", "text"],
            action: .execute { [copy] in copy(value) },
            category: "Generate"
        )]
    }

    static func parseSpec(_ spec: String) -> (Int, Unit) {
        let number = Int(spec.filter(\.isNumber)) ?? 1
        if spec.hasSuffix("w") { return (number, .words) }
        if spec.hasSuffix("s") { return (number, .sentences) }
        return (number, .paragraphs)
    }

    private func generate(count: Int, unit: Unit) -> String {
        switch unit {
        case .words:
            return (0..<count).map { Self.words[$0 % Self.words.count] }.joined(separator: " ")
        case .sentences:
            return (0..<count).map { _ in sentence() }.joined(separator: " ")
        case .paragraphs:
            return (0..<count).map { _ in
                (0..<4).map { _ in sentence() }.joined(separator: " ")
            }.joined(separator: "\n\n")
        }
    }

    private func sentence() -> String {
        let length = 8 + (Self.words.count % 5)
        let body = (0..<length).map { Self.words[$0 % Self.words.count] }.joined(separator: " ")
        return body.prefix(1).uppercased() + body.dropFirst() + "."
    }
}
