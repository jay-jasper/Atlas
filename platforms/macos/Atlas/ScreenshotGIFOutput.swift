import AppKit
import Foundation

struct ScreenshotGIFOutputItem: Equatable {
    let url: URL
    let filename: String
}

struct ScreenshotGIFOutputStore {
    private let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Atlas GIF Recordings", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func writeTemporaryGIF(_ data: Data, date: Date = Date()) throws -> ScreenshotGIFOutputItem {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let filename = Self.filename(for: date)
        let url = rootDirectory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return ScreenshotGIFOutputItem(url: url, filename: filename)
    }

    static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Atlas-GIF-\(formatter.string(from: date)).gif"
    }
}

enum ScreenshotGIFPasteboardWriter {
    static func pasteboardItem(for item: ScreenshotGIFOutputItem) -> NSPasteboardItem {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.url.absoluteString, forType: .fileURL)
        return pasteboardItem
    }

    static func copy(_ item: ScreenshotGIFOutputItem, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])
    }
}
