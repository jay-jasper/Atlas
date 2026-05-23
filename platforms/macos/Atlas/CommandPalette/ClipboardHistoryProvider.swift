import AppKit
import Foundation

protocol ClipboardReading {
    var changeCount: Int { get }
    func string() -> String?
    func imageMetadata() -> ClipboardImageMetadata?
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

    func imageMetadata() -> ClipboardImageMetadata? {
        let preferredTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        guard let type = preferredTypes.first(where: { pasteboard.data(forType: $0) != nil }),
              let data = pasteboard.data(forType: type),
              let image = NSImage(data: data) else {
            return nil
        }

        let pixelSize = image.representations.first.map {
            (width: $0.pixelsWide, height: $0.pixelsHigh)
        } ?? (width: Int(image.size.width), height: Int(image.size.height))

        return ClipboardImageMetadata(
            typeIdentifier: type.rawValue,
            pixelWidth: pixelSize.width,
            pixelHeight: pixelSize.height,
            byteCount: data.count
        )
    }

    func setString(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

final class ClipboardHistoryProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let reader: ClipboardReading
    private let store: ClipboardHistoryStoring
    private let dateProvider: () -> Date
    private var enabled: Bool
    private var onHistoryChanged: () -> Void
    private var lastChangeCount: Int?
    private let accessLogger: PrivacyPulseAccessLogging

    init(
        reader: ClipboardReading = SystemClipboardReader(),
        store: ClipboardHistoryStoring = ClipboardHistoryStore(),
        isEnabled: @escaping () -> Bool = { false },
        dateProvider: @escaping () -> Date = Date.init,
        onHistoryChanged: @escaping () -> Void = {},
        accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
    ) {
        self.reader = reader
        self.store = store
        self.enabled = isEnabled()
        self.dateProvider = dateProvider
        self.onHistoryChanged = onHistoryChanged
        self.accessLogger = accessLogger
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    func setHistoryChangedHandler(_ handler: @escaping () -> Void) {
        onHistoryChanged = handler
    }

    func results(for query: String) -> [PaletteCommand] {
        guard enabled else { return [] }
        captureCurrentClipboard()

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let matches = q.localizedCaseInsensitiveContains("clip") ? store.items() : store.search(q)
        return matches
            .prefix(Self.maxResultsCount)
            .map(command)
    }

    func captureCurrentClipboard() {
        guard enabled else { return }

        let currentChangeCount = reader.changeCount
        guard lastChangeCount != currentChangeCount else { return }
        lastChangeCount = currentChangeCount

        accessLogger.record(
            category: .clipboard,
            title: "Clipboard Read",
            detail: "Clipboard history checked for text"
        )
        if let text = reader.string(),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.addText(text, capturedAt: dateProvider())
            onHistoryChanged()
            return
        }

        if let metadata = reader.imageMetadata() {
            store.addImageMetadata(metadata, capturedAt: dateProvider())
            onHistoryChanged()
        }
    }

    private func command(for item: ClipboardHistoryItem) -> PaletteCommand {
        switch item.content {
        case .text(let text):
            return PaletteCommand(
                id: item.id,
                title: item.displayTitle,
                subtitle: "Copy from clipboard history",
                icon: .sfSymbol("doc.on.clipboard"),
                keywords: ["clipboard", "copy", text],
                action: .execute { [reader, accessLogger] in
                    accessLogger.record(
                        category: .clipboard,
                        title: "Clipboard Write",
                        detail: "Clipboard history restored text to the pasteboard"
                    )
                    reader.setString(text)
                },
                category: "Clipboard"
            )
        case .image:
            return PaletteCommand(
                id: item.id,
                title: item.displayTitle,
                subtitle: "Image metadata only",
                icon: .sfSymbol("photo"),
                keywords: ["clipboard", "image", item.searchableText],
                action: .execute {},
                category: "Clipboard"
            )
        }
    }
}
