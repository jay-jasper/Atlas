import Foundation
import UniformTypeIdentifiers

struct ScreenshotDragOutputItem: Equatable {
    let url: URL
    let filename: String
}

struct ScreenshotDragOutputStore {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Atlas Screenshot Drag Output", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    static func filename(id: UUID, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let prefix = id.uuidString.split(separator: "-").first.map(String.init) ?? id.uuidString
        return "Atlas Drag Screenshot \(formatter.string(from: date)) \(prefix).png"
    }

    static func cleanupCutoff(now: Date = Date()) -> Date {
        now.addingTimeInterval(-86_400)
    }

    func makeDragItem(
        pngData: Data,
        id: UUID,
        date: Date = Date()
    ) throws -> ScreenshotDragOutputItem {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let filename = Self.filename(id: id, date: date)
        let url = rootDirectory.appendingPathComponent(filename, isDirectory: false)
        try pngData.write(to: url, options: [.atomic])
        return ScreenshotDragOutputItem(url: url, filename: filename)
    }

    func makeItemProvider(
        pngData: Data,
        id: UUID,
        date: Date = Date()
    ) throws -> NSItemProvider {
        let item = try makeDragItem(pngData: pngData, id: id, date: date)
        let provider = NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        provider.suggestedName = item.filename
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(pngData, nil)
            return nil
        }
        return provider
    }

    func cleanupFiles(olderThan cutoffDate: Date) throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }

        let urls = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for url in urls where url.pathExtension.lowercased() == "png"
            && url.lastPathComponent.hasPrefix("Atlas Drag Screenshot ") {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { continue }

            let modificationDate = attributes[.modificationDate] as? Date ?? .distantFuture
            if modificationDate < cutoffDate {
                try fileManager.removeItem(at: url)
            }
        }
    }
}
