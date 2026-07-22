import AppKit
import Foundation
import UniformTypeIdentifiers

/// Export container formats (all ImageIO-native; WebP/AVIF deliberately
/// excluded — they'd need third-party encoders).
enum ScreenshotExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case heic

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }

    var usesQuality: Bool { self != .png }

    /// Transcode PNG data to this format (quality 0…1, lossy formats only).
    func encode(pngData: Data, quality: Double) -> Data? {
        guard self != .png else { return pngData }
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            contentType.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let clamped = max(0.1, min(1.0, quality))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: clamped] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

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
        _ = pasteboard.clearContents()
        _ = pasteboard.setData(data, forType: .png)
    }

    static func writePNG(_ data: Data, to directory: URL, date: Date = Date()) throws -> URL {
        let url = directory.appendingPathComponent(filename(for: date))
        try data.write(to: url, options: .atomic)
        return url
    }

    static func savePNGWithPanel(_ data: Data, suggestedDate: Date = Date()) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = ScreenshotExportFormat.allCases.map(\.contentType)
        panel.nameFieldStringValue = filename(for: suggestedDate)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        // Transcode when the user picked a non-PNG extension in the panel.
        let format = ScreenshotExportFormat.allCases.first {
            $0.fileExtension == url.pathExtension.lowercased()
                || ($0 == .jpeg && url.pathExtension.lowercased() == "jpeg")
        } ?? .png
        let output = format.encode(pngData: data, quality: 0.9) ?? data

        do {
            try output.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
