import AppKit
import Foundation
import SwiftUI

enum FlowInboxItemKind: String, Codable {
    case clipboard
    case screenshot
    case favorite
    case file
}

struct FlowInboxFavorite: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var body: String
    var source: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, body: String, source: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.source = source
        self.createdAt = createdAt
    }
}

struct FlowInboxFileItem: Codable, Equatable, Identifiable {
    let id: UUID
    var filePath: String
    var addedAt: Date

    init(id: UUID = UUID(), filePath: String, addedAt: Date = Date()) {
        self.id = id
        self.filePath = filePath
        self.addedAt = addedAt
    }

    var url: URL {
        URL(fileURLWithPath: filePath)
    }
}

struct FlowInboxItem: Identifiable, Equatable {
    let id: UUID
    let kind: FlowInboxItemKind
    let title: String
    let subtitle: String
    let body: String
    let createdAt: Date
    let fileURL: URL?
}

final class FlowInboxStore {
    private struct PersistedState: Codable {
        var favorites: [FlowInboxFavorite]
        var files: [FlowInboxFileItem]
    }

    private let url: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("Flow Inbox", isDirectory: true)
            .appendingPathComponent("inbox.json"),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadFavorites() -> [FlowInboxFavorite] {
        loadState().favorites
    }

    func loadFiles() -> [FlowInboxFileItem] {
        loadState().files.filter { fileManager.fileExists(atPath: $0.filePath) }
    }

    func addFavorite(title: String, body: String, source: String) {
        var state = loadState()
        state.favorites.insert(FlowInboxFavorite(title: title, body: body, source: source), at: 0)
        save(state)
    }

    func removeFavorite(id: UUID) {
        var state = loadState()
        state.favorites.removeAll { $0.id == id }
        save(state)
    }

    func addFile(url: URL) {
        var state = loadState()
        state.files.removeAll { $0.filePath == url.path }
        state.files.insert(FlowInboxFileItem(filePath: url.path), at: 0)
        save(state)
    }

    func removeFile(id: UUID) {
        var state = loadState()
        state.files.removeAll { $0.id == id }
        save(state)
    }

    func buildItems(
        clipboardStore: ClipboardHistoryStoring,
        screenshotStore: ScreenshotLibraryStore
    ) -> [FlowInboxItem] {
        var items: [FlowInboxItem] = []

        for favorite in loadFavorites() {
            items.append(
                FlowInboxItem(
                    id: favorite.id,
                    kind: .favorite,
                    title: favorite.title,
                    subtitle: "Favorite • \(favorite.source)",
                    body: favorite.body,
                    createdAt: favorite.createdAt,
                    fileURL: nil
                )
            )
        }

        for file in loadFiles() {
            items.append(
                FlowInboxItem(
                    id: file.id,
                    kind: .file,
                    title: file.url.lastPathComponent,
                    subtitle: "Quick File Send",
                    body: file.filePath,
                    createdAt: file.addedAt,
                    fileURL: file.url
                )
            )
        }

        for item in clipboardStore.items().prefix(10) {
            items.append(
                FlowInboxItem(
                    id: item.id,
                    kind: .clipboard,
                    title: item.displayTitle,
                    subtitle: "Clipboard",
                    body: item.searchableText,
                    createdAt: item.capturedAt,
                    fileURL: nil
                )
            )
        }

        let screenshotItems = (try? screenshotStore.loadItems()) ?? []
        for item in screenshotItems.prefix(10) {
            let body = [item.recognizedText, item.translatedText]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            items.append(
                FlowInboxItem(
                    id: item.id,
                    kind: .screenshot,
                    title: item.filename,
                    subtitle: "Screenshot • \(item.source)",
                    body: body,
                    createdAt: item.capturedAt,
                    fileURL: screenshotStore.pngURL(for: item)
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.title < rhs.title
        }
    }

    private func loadState() -> PersistedState {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(PersistedState.self, from: data) else {
            return PersistedState(favorites: [], files: [])
        }
        return state
    }

    private func save(_ state: PersistedState) {
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

struct FlowInboxPanel: View {
    let store: FlowInboxStore
    let clipboardStore: ClipboardHistoryStoring
    let screenshotStore: ScreenshotLibraryStore
    let scratchpadStore: ScratchpadStore
    let behaviorRules: SceneBehaviorRules
    let onShowStatus: (String) -> Void

    @State private var items: [FlowInboxItem] = []
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Flow Inbox", systemImage: "tray.full")
                    .font(.headline)
                Spacer()
                Button("Add File", action: addFile)
                Button("Refresh", action: reload)
            }

            TextField("Search recent content", text: $query)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredItems) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if !item.body.isEmpty {
                                Text(item.body)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(4)
                            }

                            HStack {
                                if item.kind != .favorite {
                                    Button("Favorite") {
                                        store.addFavorite(title: item.title, body: item.body, source: item.subtitle)
                                        reload()
                                        onShowStatus("Saved to inbox favorites")
                                    }
                                }
                                Button("Copy") {
                                    copy(item)
                                }
                                if let fileURL = item.fileURL {
                                    ShareLink(item: fileURL) {
                                        Text("Share")
                                    }
                                } else {
                                    ShareLink(item: shareText(for: item)) {
                                        Text("Share")
                                    }
                                }
                                Button("Scratchpad") {
                                    saveToScratchpad(item)
                                }
                                if let fileURL = item.fileURL {
                                    Button("Open") {
                                        NSWorkspace.shared.open(fileURL)
                                    }
                                    Button("Reveal") {
                                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(minHeight: 220)
        }
        .onAppear(perform: reload)
    }

    private var filteredItems: [FlowInboxItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return prioritized(items)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return prioritized(items).filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
                || $0.body.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func prioritized(_ items: [FlowInboxItem]) -> [FlowInboxItem] {
        if behaviorRules.preferInboxFavorites {
            return items.sorted { lhs, rhs in
                if lhs.kind == .favorite && rhs.kind != .favorite { return true }
                if lhs.kind != .favorite && rhs.kind == .favorite { return false }
                return lhs.createdAt > rhs.createdAt
            }
        }
        return items
    }

    private func reload() {
        items = store.buildItems(clipboardStore: clipboardStore, screenshotStore: screenshotStore)
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addFile(url: url)
        reload()
        onShowStatus("Added file to Flow Inbox")
    }

    private func copy(_ item: FlowInboxItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let fileURL = item.fileURL {
            pasteboard.writeObjects([fileURL as NSURL])
        } else {
            pasteboard.setString(item.body.isEmpty ? item.title : item.body, forType: .string)
        }
        onShowStatus("Copied inbox item")
    }

    private func saveToScratchpad(_ item: FlowInboxItem) {
        let title = item.title
        let body = item.body.isEmpty ? item.subtitle : item.body
        do {
            _ = try scratchpadStore.create(ScratchpadDraft(title: title, markdown: body))
            onShowStatus("Saved inbox item to Scratchpad")
        } catch {
            onShowStatus(error.localizedDescription)
        }
    }

    private func shareText(for item: FlowInboxItem) -> String {
        let content = item.body.isEmpty ? item.title : item.body
        if item.subtitle.isEmpty {
            return content
        }
        return "\(item.title)\n\(item.subtitle)\n\n\(content)"
    }
}

struct FlowInboxCommandProvider: CommandProviding {
    let isEnabled: () -> Bool

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }
        let commands = [
            PaletteCommand(
                id: UUID(),
                title: "Flow Inbox",
                subtitle: "Recent clipboard, screenshots, favorites, and files",
                icon: .sfSymbol("tray.full"),
                keywords: ["flow", "inbox", "clipboard", "screenshot", "recent"],
                action: .push(.flowInbox),
                category: "Flow Inbox"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Text Toolbox",
                subtitle: "Convert and clean text quickly",
                icon: .sfSymbol("character.textbox"),
                keywords: ["text", "json", "base64", "url", "timestamp"],
                action: .push(.textToolbox),
                category: "Flow Inbox"
            ),
        ]

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return commands
        }

        return commands.filter { command in
            command.title.lowercased().contains(trimmed)
                || command.subtitle?.lowercased().contains(trimmed) == true
                || command.keywords.contains(where: { $0.contains(trimmed) })
        }
    }
}

enum TextToolboxMode: String, CaseIterable, Identifiable {
    case uppercase
    case lowercase
    case trimmed
    case jsonPretty = "json-pretty"
    case base64Encode = "base64-encode"
    case base64Decode = "base64-decode"
    case urlEncode = "url-encode"
    case urlDecode = "url-decode"
    case timestampISO = "timestamp-iso"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uppercase:
            return "Uppercase"
        case .lowercase:
            return "Lowercase"
        case .trimmed:
            return "Trim Whitespace"
        case .jsonPretty:
            return "Format JSON"
        case .base64Encode:
            return "Base64 Encode"
        case .base64Decode:
            return "Base64 Decode"
        case .urlEncode:
            return "URL Encode"
        case .urlDecode:
            return "URL Decode"
        case .timestampISO:
            return "Timestamp to ISO-8601"
        }
    }
}

struct TextToolboxView: View {
    @State private var input = ""
    @State private var mode: TextToolboxMode = .trimmed

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Text Toolbox", systemImage: "character.textbox")
                .font(.headline)

            Picker("Transform", selection: $mode) {
                ForEach(TextToolboxMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2)))

            VStack(alignment: .leading, spacing: 8) {
                Text("Output")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Use Output as Input") {
                    input = output
                }
                Button("Copy Output") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(output, forType: .string)
                }
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 420)
    }

    private var output: String {
        switch mode {
        case .uppercase:
            return input.uppercased()
        case .lowercase:
            return input.lowercased()
        case .trimmed:
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        case .jsonPretty:
            guard let data = input.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let formattedData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
                  let string = String(data: formattedData, encoding: .utf8) else {
                return "Invalid JSON"
            }
            return string
        case .base64Encode:
            return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: input),
                  let string = String(data: data, encoding: .utf8) else {
                return "Invalid Base64"
            }
            return string
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        case .urlDecode:
            return input.removingPercentEncoding ?? "Invalid URL encoding"
        case .timestampISO:
            guard let timestamp = Double(input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return "Invalid timestamp"
            }
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
        }
    }
}
