import SwiftUI

struct ClipboardHistoryPanel: View {
    let items: [ClipboardHistoryItem]
    let onCopyText: (String) -> Void
    let onDelete: (UUID) -> Void
    let onClear: () -> Void
    @Binding var query: String

    private var filteredItems: [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.searchableText.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clipboard History")
                    .font(.headline)
                Spacer()
                Button("Clear All", action: onClear)
                    .disabled(items.isEmpty)
            }

            Text("Atlas stores copied text locally on this Mac. Images are recorded as metadata only; image pixels are not saved.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Search clipboard history", text: $query)
                .textFieldStyle(.roundedBorder)

            if filteredItems.isEmpty {
                Text(query.isEmpty ? "No clipboard history yet." : "No matching clipboard items.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(filteredItems) { item in
                        ClipboardHistoryRow(
                            item: item,
                            onCopyText: onCopyText,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let onCopyText: (String) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.textValue == nil ? "photo" : "doc.on.clipboard")
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let text = item.textValue {
                Button("Copy") {
                    onCopyText(text)
                }
            }

            Button("Delete") {
                onDelete(item.id)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subtitle: String {
        switch item.content {
        case .text(let text):
            return "\(text.count) characters"
        case .image(let metadata):
            if let byteCount = metadata.byteCount {
                return "\(metadata.typeIdentifier), \(byteCount) bytes, pixels not stored"
            }
            return "\(metadata.typeIdentifier), pixels not stored"
        }
    }
}
