import AppKit
import Foundation

protocol ScreenshotPasteboardWriting {
    func clearContents() -> Int
    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: ScreenshotPasteboardWriting {}

enum ScreenshotOutput {
    static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Atlas Screenshot \(formatter.string(from: date)).png"
    }

    static func copyPNGToClipboard(
        _ data: Data,
        pasteboard: ScreenshotPasteboardWriting = NSPasteboard.general,
        accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
    ) {
        accessLogger.record(
            category: .clipboard,
            title: "Clipboard Write",
            detail: "Screenshot copied PNG data to the pasteboard"
        )
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    static func writePNG(_ data: Data, to directory: URL, date: Date = Date()) throws -> URL {
        let url = directory.appendingPathComponent(filename(for: date))
        try data.write(to: url, options: .atomic)
        return url
    }

    static func savePNGWithPanel(_ data: Data, suggestedDate: Date = Date()) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = filename(for: suggestedDate)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
