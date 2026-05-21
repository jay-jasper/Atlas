import AppKit
import Foundation

struct ClipboardHistoryItem: Equatable, Sendable {
    let id: UUID
    let text: String
    let capturedAt: Date
}

protocol ClipboardReading {
    var changeCount: Int { get }
    func string() -> String?
    func setString(_ text: String)
}

final class SystemClipboardReader: ClipboardReading {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func string() -> String? {
        pasteboard.string(forType: .string)
    }

    func setString(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

final class ClipboardHistoryProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let reader: ClipboardReading
    private let maxHistoryCount: Int
    private let dateProvider: () -> Date
    private var lastChangeCount: Int?
    private(set) var items: [ClipboardHistoryItem] = []

    init(
        reader: ClipboardReading = SystemClipboardReader(),
        maxHistoryCount: Int = 20,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.reader = reader
        self.maxHistoryCount = maxHistoryCount
        self.dateProvider = dateProvider
    }

    func results(for query: String) -> [PaletteCommand] {
        captureCurrentClipboard()

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return items
            .filter { item in
                q.localizedCaseInsensitiveContains("clip") ||
                item.text.localizedCaseInsensitiveContains(q)
            }
            .prefix(Self.maxResultsCount)
            .map { item in
                PaletteCommand(
                    id: item.id,
                    title: Self.title(for: item.text),
                    subtitle: "Copy from clipboard history",
                    icon: .sfSymbol("doc.on.clipboard"),
                    keywords: ["clipboard", "copy", item.text],
                    action: .execute { [reader] in
                        reader.setString(item.text)
                    },
                    category: "Clipboard"
                )
            }
    }

    func captureCurrentClipboard() {
        let currentChangeCount = reader.changeCount
        guard lastChangeCount != currentChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard let text = reader.string() else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard items.first?.text != text else { return }

        items.insert(
            ClipboardHistoryItem(id: UUID(), text: text, capturedAt: dateProvider()),
            at: 0
        )

        if items.count > maxHistoryCount {
            items.removeLast(items.count - maxHistoryCount)
        }
    }

    private static func title(for text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? text
        return String(firstLine.prefix(80))
    }
}
