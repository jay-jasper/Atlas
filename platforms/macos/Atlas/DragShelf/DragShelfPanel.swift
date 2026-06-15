import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DragShelfPanel: View {
    @ObservedObject var service: DragShelfService
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Drag Shelf", systemImage: "tray.full")
                    .font(.headline)
                Spacer()
                if !service.items.isEmpty {
                    Button("Clear") { service.clear() }.controlSize(.small)
                }
            }

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(height: 50)
                .overlay(
                    Text(service.items.isEmpty ? "Drop files here to stage them" : "\(service.items.count) staged — drop more")
                        .font(.caption).foregroundStyle(.secondary)
                )
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    loadURLs(from: providers)
                    return true
                }

            ForEach(service.items) { item in
                HStack {
                    Image(systemName: "doc").font(.caption2).foregroundStyle(.secondary)
                    Text(item.name).font(.caption).lineLimit(1)
                    Spacer()
                    Button(role: .destructive) { service.remove(id: item.id) } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            if !service.items.isEmpty {
                Button("Move All To…") { chooseDestination() }
                    .controlSize(.small)
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func loadURLs(from providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    Task { @MainActor in service.add(urls: [url]) }
                }
            }
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            service.copyAll(to: url)
        }
    }
}
