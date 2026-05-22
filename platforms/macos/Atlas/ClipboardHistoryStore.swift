import Foundation

struct ClipboardImageMetadata: Codable, Equatable, Sendable {
    let typeIdentifier: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int?

    var displayTitle: String {
        "Image \(pixelWidth) x \(pixelHeight)"
    }

    var searchableText: String {
        var parts = ["image", typeIdentifier, "\(pixelWidth) x \(pixelHeight)"]
        if let byteCount {
            parts.append("\(byteCount) bytes")
        }
        return parts.joined(separator: " ")
    }
}

enum ClipboardHistoryContent: Codable, Equatable, Sendable {
    case text(String)
    case image(ClipboardImageMetadata)

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case image
    }

    private enum Kind: String, Codable {
        case text
        case image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(try container.decode(ClipboardImageMetadata.self, forKey: .image))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .image(let metadata):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(metadata, forKey: .image)
        }
    }
}

struct ClipboardHistoryItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let content: ClipboardHistoryContent
    let capturedAt: Date

    var displayTitle: String {
        switch content {
        case .text(let text):
            let firstLine = text
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? text
            return String(firstLine.prefix(80))
        case .image(let metadata):
            return metadata.displayTitle
        }
    }

    var searchableText: String {
        switch content {
        case .text(let text):
            return text
        case .image(let metadata):
            return metadata.searchableText
        }
    }

    var textValue: String? {
        if case .text(let text) = content {
            return text
        }
        return nil
    }
}

protocol ClipboardHistoryStoring: AnyObject {
    func items() -> [ClipboardHistoryItem]
    func search(_ query: String) -> [ClipboardHistoryItem]
    func addText(_ text: String, capturedAt: Date)
    func addImageMetadata(_ metadata: ClipboardImageMetadata, capturedAt: Date)
    func delete(id: UUID)
    func clear()
}

final class ClipboardHistoryStore: ClipboardHistoryStoring {
    private static let storageKey = "clipboardHistory.items"

    private let defaults: UserDefaults
    private let maxHistoryCount: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, maxHistoryCount: Int = 50) {
        self.defaults = defaults
        self.maxHistoryCount = maxHistoryCount
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func items() -> [ClipboardHistoryItem] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? decoder.decode([ClipboardHistoryItem].self, from: data) else {
            return []
        }
        return Array(decoded.prefix(maxHistoryCount))
    }

    func search(_ query: String) -> [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items() }
        return items().filter { $0.searchableText.localizedCaseInsensitiveContains(trimmed) }
    }

    func addText(_ text: String, capturedAt: Date) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item = ClipboardHistoryItem(id: UUID(), content: .text(text), capturedAt: capturedAt)
        save(inserted: item) { existing in
            existing.textValue == text
        }
    }

    func addImageMetadata(_ metadata: ClipboardImageMetadata, capturedAt: Date) {
        let item = ClipboardHistoryItem(id: UUID(), content: .image(metadata), capturedAt: capturedAt)
        save(inserted: item) { existing in
            existing.content == .image(metadata)
        }
    }

    func delete(id: UUID) {
        save(items().filter { $0.id != id })
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func save(inserted item: ClipboardHistoryItem, removing shouldRemove: (ClipboardHistoryItem) -> Bool) {
        let remaining = items().filter { !shouldRemove($0) }
        save([item] + remaining)
    }

    private func save(_ newItems: [ClipboardHistoryItem]) {
        let retained = Array(newItems.prefix(maxHistoryCount))
        if let data = try? encoder.encode(retained) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
