import Foundation

struct ScreenshotLibraryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let filename: String
    let capturedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let source: String
    var recognizedText: String
    var translatedText: String

    var dimensionsText: String {
        "\(pixelWidth) x \(pixelHeight)"
    }
}

enum ScreenshotLibraryError: LocalizedError, Equatable {
    case missingImage(UUID)

    var errorDescription: String? {
        switch self {
        case .missingImage:
            return "Screenshot image is missing from the local library"
        }
    }
}

final class ScreenshotLibraryStore {
    private let rootDirectory: URL
    private let imagesDirectory: URL
    private let indexURL: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = ScreenshotLibraryStore.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.imagesDirectory = rootDirectory.appendingPathComponent("Images", isDirectory: true)
        self.indexURL = rootDirectory.appendingPathComponent("index.json", isDirectory: false)
        self.fileManager = fileManager
    }

    func loadItems() throws -> [ScreenshotLibraryItem] {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexURL)
        let items = try decoder().decode([ScreenshotLibraryItem].self, from: data)
        return sorted(items)
    }

    func addScreenshot(
        pngData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        source: String,
        capturedAt: Date = Date()
    ) throws -> ScreenshotLibraryItem {
        try createDirectories()

        let id = UUID()
        let filename = "\(id.uuidString).png"
        let item = ScreenshotLibraryItem(
            id: id,
            filename: filename,
            capturedAt: capturedAt,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            source: source,
            recognizedText: "",
            translatedText: ""
        )

        try pngData.write(to: pngURL(for: item), options: .atomic)

        var items = try loadItems()
        items.append(item)
        try save(items)

        return item
    }

    func updateText(id: UUID, recognizedText: String?, translatedText: String?) throws {
        var items = try loadItems()
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        if let recognizedText {
            items[index].recognizedText = recognizedText
        }
        if let translatedText {
            items[index].translatedText = translatedText
        }

        try save(items)
    }

    func search(query: String) throws -> [ScreenshotLibraryItem] {
        let items = try loadItems()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        return items.filter { item in
            item.source.localizedCaseInsensitiveContains(trimmedQuery)
                || item.recognizedText.localizedCaseInsensitiveContains(trimmedQuery)
                || item.translatedText.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    func delete(id: UUID) throws {
        var items = try loadItems()
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let item = items.remove(at: index)
        let imageURL = pngURL(for: item)
        try save(items)

        if fileManager.fileExists(atPath: imageURL.path) {
            try fileManager.removeItem(at: imageURL)
        }
    }

    func pngURL(for item: ScreenshotLibraryItem) -> URL {
        imagesDirectory.appendingPathComponent(item.filename, isDirectory: false)
    }

    func pngData(for item: ScreenshotLibraryItem) throws -> Data {
        let imageURL = pngURL(for: item)
        guard fileManager.fileExists(atPath: imageURL.path) else {
            throw ScreenshotLibraryError.missingImage(item.id)
        }

        return try Data(contentsOf: imageURL)
    }

    private static func defaultRootDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("Screenshot Library", isDirectory: true)
    }

    private func createDirectories() throws {
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    private func save(_ items: [ScreenshotLibraryItem]) throws {
        try createDirectories()
        let data = try encoder().encode(sorted(items))
        try data.write(to: indexURL, options: .atomic)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.fractionalISO8601Formatter().string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = Self.fractionalISO8601Formatter().date(from: value) {
                return date
            }
            if let date = Self.compatibilityISO8601Formatter().date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 date string"
            )
        }
        return decoder
    }

    private static func fractionalISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func compatibilityISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private func sorted(_ items: [ScreenshotLibraryItem]) -> [ScreenshotLibraryItem] {
        items.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt > rhs.capturedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
