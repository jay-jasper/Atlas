import AppKit
import SwiftUI

struct RSSPanel: View {
    @ObservedObject var service: RSSService
    @State private var newFeedURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("RSS Reader", systemImage: "dot.radiowaves.up.forward")
                    .font(.headline)
                Spacer()
                if service.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh") { Task { await service.refreshAll() } }
                        .controlSize(.small)
                }
            }

            if !service.subscriptions.isEmpty {
                ForEach(service.subscriptions) { subscription in
                    HStack {
                        Image(systemName: "checkmark.seal").font(.caption2).foregroundStyle(.secondary)
                        Text(subscription.title).font(.caption).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) { service.delete(id: subscription.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider()
            }

            ForEach(service.items.prefix(15)) { item in
                Button {
                    if let url = URL(string: item.link) { NSWorkspace.shared.open(url) }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.caption.weight(.medium)).lineLimit(1)
                        if !item.summary.isEmpty {
                            Text(item.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            HStack {
                TextField("https://example.com/feed.xml", text: $newFeedURL)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let url = newFeedURL
                    newFeedURL = ""
                    Task { await service.addFeed(url: url) }
                }
                .disabled(newFeedURL.isEmpty)
            }
        }
    }
}
