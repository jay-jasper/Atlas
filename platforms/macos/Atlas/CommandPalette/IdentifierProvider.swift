import Foundation

/// Generates identifiers: `uuid` for a v4 UUID, `nanoid [length]` for a
/// URL-safe NanoID (default length 21). Copies the value on selection.
final class IdentifierProvider: CommandProviding {
    private let copy: PasteboardWriting
    private let makeUUID: () -> String
    private let randomByte: () -> UInt8

    init(
        copy: @escaping PasteboardWriting = Pasteboard.system,
        makeUUID: @escaping () -> String = { UUID().uuidString },
        randomByte: @escaping () -> UInt8 = { UInt8.random(in: 0...255) }
    ) {
        self.copy = copy
        self.makeUUID = makeUUID
        self.randomByte = randomByte
    }

    private static let nanoIDAlphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_-")

    func results(for query: String) -> [PaletteCommand] {
        let parts = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard let keyword = parts.first else { return [] }

        switch keyword {
        case "uuid", "guid":
            let value = makeUUID()
            return [command(title: value, subtitle: "UUID v4 · ↵ to copy", value: value)]
        case "nanoid", "nano":
            let length = parts.count > 1 ? (Int(parts[1]) ?? 21) : 21
            let clamped = min(max(length, 1), 256)
            let value = nanoID(length: clamped)
            return [command(title: value, subtitle: "NanoID (\(clamped)) · ↵ to copy", value: value)]
        default:
            return []
        }
    }

    private func nanoID(length: Int) -> String {
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            let index = Int(randomByte()) % Self.nanoIDAlphabet.count
            result.append(Self.nanoIDAlphabet[index])
        }
        return result
    }

    private func command(title: String, subtitle: String, value: String) -> PaletteCommand {
        PaletteCommand(
            id: UUID(),
            title: title,
            subtitle: subtitle,
            icon: .sfSymbol("number"),
            keywords: ["uuid", "nanoid", "id", "generate"],
            action: .execute { [copy] in copy(value) },
            category: "Generate"
        )
    }
}
