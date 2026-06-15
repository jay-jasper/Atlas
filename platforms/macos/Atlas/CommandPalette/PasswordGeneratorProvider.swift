import Foundation

/// Generates passwords: `password [length] [symbols] [no-digits]`.
/// Defaults to a 16-character alphanumeric password; `symbols` adds
/// punctuation. Copies the value on selection.
final class PasswordGeneratorProvider: CommandProviding {
    private let copy: PasteboardWriting
    private let pick: (Int) -> Int // returns an index in 0..<count

    init(
        copy: @escaping PasteboardWriting = Pasteboard.system,
        pick: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }
    ) {
        self.copy = copy
        self.pick = pick
    }

    private static let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let digits = "0123456789"
    private static let symbols = "!@#$%^&*()-_=+[]{};:,.?"

    func results(for query: String) -> [PaletteCommand] {
        let parts = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard let keyword = parts.first, keyword == "password" || keyword == "pass" || keyword == "pwd" else {
            return []
        }

        let options = Set(parts.dropFirst())
        let length = options.compactMap { Int($0) }.first ?? 16
        let clamped = min(max(length, 4), 128)
        var alphabet = Self.letters
        if !options.contains("no-digits") { alphabet += Self.digits }
        if options.contains("symbols") { alphabet += Self.symbols }

        let value = generate(length: clamped, from: Array(alphabet))
        var descriptor = "\(clamped) chars"
        if options.contains("symbols") { descriptor += " · symbols" }

        return [PaletteCommand(
            id: UUID(),
            title: value,
            subtitle: "Password (\(descriptor)) · ↵ to copy",
            icon: .sfSymbol("key.fill"),
            keywords: ["password", "generate", "secure", "random"],
            action: .execute { [copy] in copy(value) },
            category: "Generate"
        )]
    }

    private func generate(length: Int, from alphabet: [Character]) -> String {
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(alphabet[pick(alphabet.count)])
        }
        return result
    }
}
