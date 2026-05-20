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
    @Binding var query: String

    var body: some View {
        let state = ScreenshotLibraryPanelState(items: items, query: query)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Screenshot Library")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
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
                            onOpen: onOpen,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
    }
}

private struct ScreenshotLibraryRow: View {
    let item: ScreenshotLibraryItem
    let onOpen: (ScreenshotLibraryItem) -> Void
    let onDelete: (ScreenshotLibraryItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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

                if !item.recognizedText.isEmpty {
                    Text(item.recognizedText)
                        .font(.caption)
                        .lineLimit(2)
                }

                if !item.translatedText.isEmpty {
                    Text(item.translatedText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                onOpen(item)
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help("Open screenshot")

            Button {
                onDelete(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete screenshot")
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
