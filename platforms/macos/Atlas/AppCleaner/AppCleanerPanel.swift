import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppCleanerPanel: View {
    @ObservedObject var service: AppCleanerService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("App Cleaner", systemImage: "trash.circle")
                    .font(.headline)
                Spacer()
                Button("Choose App…") { chooseApp() }
                    .controlSize(.small)
            }

            if !service.appName.isEmpty {
                HStack {
                    Text(service.appName).font(.subheadline.weight(.semibold))
                    Spacer()
                    let total = service.leftovers.reduce(0) { $0 + $1.size }
                    Text(DiskUsageScanner.formatBytes(total))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            ForEach(service.leftovers) { item in
                HStack {
                    Text(item.category)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    Text((item.path as NSString).lastPathComponent)
                        .font(.caption).lineLimit(1)
                    Spacer()
                    Text(DiskUsageScanner.formatBytes(item.size))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            if !service.leftovers.isEmpty {
                Button("Move All to Trash", role: .destructive) {
                    service.removeToTrash(service.leftovers)
                }
                .controlSize(.small)
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            service.scan(appURL: url)
        }
    }
}
