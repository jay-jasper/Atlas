import SwiftUI

struct ScreenshotLibraryPanelState: Equatable {
    let items: [ScreenshotLibraryItem]
    var query: String

    var visibleItems: [ScreenshotLibraryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        return items.filter { item in
            item.source.localizedCaseInsensitiveContains(trimmedQuery)
                || item.recognizedText.localizedCaseInsensitiveContains(trimmedQuery)
                || item.translatedText.localizedCaseInsensitiveContains(trimmedQuery)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }
    }

    var countText: String {
        let visibleCount = visibleItems.count
        guard visibleCount != items.count else {
            return "\(items.count) \(items.count == 1 ? "screenshot" : "screenshots")"
        }

        return "\(visibleCount) of \(items.count) screenshots"
    }

    var emptyText: String {
        items.isEmpty ? "No screenshots saved yet" : "No screenshots match the search"
    }
}

struct ScreenshotLibraryPanel: View {
    let items: [ScreenshotLibraryItem]
    let onOpen: (ScreenshotLibraryItem) -> Void
    let onDelete: (ScreenshotLibraryItem) -> Void
    let pngURL: ((ScreenshotLibraryItem) -> URL?)?
    let onRunOCR: (() -> Void)?
    let onRunTranslation: (() -> Void)?
    let onUpdateTags: ((ScreenshotLibraryItem, [String]) -> Void)?
    let onCopyText: ((String) -> Void)?
    @Binding var query: String

    init(
        items: [ScreenshotLibraryItem],
        onOpen: @escaping (ScreenshotLibraryItem) -> Void,
        onDelete: @escaping (ScreenshotLibraryItem) -> Void,
        pngURL: ((ScreenshotLibraryItem) -> URL?)? = nil,
        onRunOCR: (() -> Void)? = nil,
        onRunTranslation: (() -> Void)? = nil,
        onUpdateTags: ((ScreenshotLibraryItem, [String]) -> Void)? = nil,
        onCopyText: ((String) -> Void)? = nil,
        query: Binding<String>
    ) {
        self.items = items
        self.onOpen = onOpen
        self.onDelete = onDelete
        self.pngURL = pngURL
        self.onRunOCR = onRunOCR
        self.onRunTranslation = onRunTranslation
        self.onUpdateTags = onUpdateTags
        self.onCopyText = onCopyText
        self._query = query
    }

    var body: some View {
        let state = ScreenshotLibraryPanelState(items: items, query: query)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Screenshot Library")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let onRunOCR, items.contains(where: { $0.recognizedText.isEmpty }) {
                    Button("OCR All") { onRunOCR() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                if let onRunTranslation, items.contains(where: { !$0.recognizedText.isEmpty && $0.translatedText.isEmpty }) {
                    Button("Translate All") { onRunTranslation() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                Text(state.countText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField("Search screenshots", text: $query)
                .textFieldStyle(.roundedBorder)

            if state.visibleItems.isEmpty {
                Text(state.emptyText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.visibleItems) { item in
                        ScreenshotLibraryRow(
                            item: item,
                            thumbnailURL: pngURL?(item),
                            onOpen: onOpen,
                            onDelete: onDelete,
                            onUpdateTags: onUpdateTags,
                            onCopyText: onCopyText
                        )
                    }
                }
            }
        }
    }
}

private struct ScreenshotLibraryRow: View {
    let item: ScreenshotLibraryItem
    let thumbnailURL: URL?
    let onOpen: (ScreenshotLibraryItem) -> Void
    let onDelete: (ScreenshotLibraryItem) -> Void
    let onUpdateTags: ((ScreenshotLibraryItem, [String]) -> Void)?
    let onCopyText: ((String) -> Void)?

    @State private var thumbnail: NSImage?
    @State private var isEditingTags: Bool = false
    @State private var tagDraft: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.source)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(item.dimensionsText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Self.dateFormatter.string(from: item.capturedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !item.tags.isEmpty {
                    tagsView
                }

                if !item.recognizedText.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text(item.recognizedText)
                            .font(.caption)
                            .lineLimit(2)
                        if let onCopyText {
                            Button {
                                onCopyText(item.recognizedText)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.borderless)
                            .help("Copy recognized text")
                        }
                    }
                }

                if !item.translatedText.isEmpty {
                    Text(item.translatedText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if isEditingTags {
                    tagEditor
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Button {
                    onOpen(item)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open screenshot")

                if onUpdateTags != nil {
                    Button {
                        tagDraft = ""
                        isEditingTags.toggle()
                    } label: {
                        Image(systemName: "tag")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit tags")
                }

                Button {
                    onDelete(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete screenshot")
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: thumbnailURL) {
            guard let url = thumbnailURL,
                  let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data) else { return }
            let scaled = thumbnail(from: image, maxSize: CGSize(width: 56, height: 42))
            await MainActor.run { thumbnail = scaled }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 56, height: 42)
                .overlay(Image(systemName: "photo").foregroundColor(.secondary).font(.caption))
        }
    }

    @ViewBuilder
    private var tagsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(item.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var tagEditor: some View {
        HStack(spacing: 4) {
            TextField("Add tag, comma-separated", text: $tagDraft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            Button("Save") {
                let newTags = tagDraft
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                let merged = Array(Set(item.tags + newTags)).sorted()
                onUpdateTags?(item, merged)
                isEditingTags = false
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        if !item.tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(item.tags, id: \.self) { tag in
                    Button {
                        let remaining = item.tags.filter { $0 != tag }
                        onUpdateTags?(item, remaining)
                    } label: {
                        HStack(spacing: 2) {
                            Text(tag).font(.caption2)
                            Image(systemName: "xmark").font(.system(size: 8))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func thumbnail(from image: NSImage, maxSize: CGSize) -> NSImage {
        let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: size))
        result.unlockFocus()
        return result
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
