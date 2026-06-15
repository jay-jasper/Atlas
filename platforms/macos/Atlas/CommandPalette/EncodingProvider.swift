import Foundation

/// Encodes/decodes text: `b64 <text>`, `b64decode <text>`,
/// `urlencode <text>`, `urldecode <text>`. Copies the result on selection.
final class EncodingProvider: CommandProviding {
    private let copy: PasteboardWriting

    init(copy: @escaping PasteboardWriting = Pasteboard.system) {
        self.copy = copy
    }

    func results(for query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2 else { return [] }
        let keyword = parts[0].lowercased()
        let text = parts[1]

        let result: String?
        let label: String
        switch keyword {
        case "b64", "base64", "b64encode":
            result = Data(text.utf8).base64EncodedString()
            label = "Base64 encode"
        case "b64decode", "base64decode":
            result = Data(base64Encoded: text).flatMap { String(data: $0, encoding: .utf8) }
            label = "Base64 decode"
        case "urlencode":
            result = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            label = "URL encode"
        case "urldecode":
            result = text.removingPercentEncoding
            label = "URL decode"
        default:
            return []
        }

        guard let value = result else { return [] }
        return [PaletteCommand(
            id: UUID(),
            title: value,
            subtitle: "\(label) · ↵ to copy",
            icon: .sfSymbol("arrow.left.arrow.right"),
            keywords: ["base64", "url", "encode", "decode"],
            action: .execute { [copy] in copy(value) },
            category: "Encode"
        )]
    }
}
