import AppKit
import SwiftUI

struct PluginsPanel: View {
    @ObservedObject var service: PluginsService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Plugins", systemImage: "puzzlepiece.extension")
                .font(.headline)

            HStack {
                Button("Install Package…") { choosePackage() }
                Button("Refresh") { service.refresh() }
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if service.plugins.isEmpty {
                Text("No plugins installed. Install a WASM or MCP plugin to extend Atlas.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(service.plugins) { plugin in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(plugin.name).font(.subheadline.weight(.semibold))
                            Text(plugin.version).font(.caption2).foregroundStyle(.secondary)
                            Text(plugin.track.uppercased())
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                            Spacer()
                            Button(role: .destructive) { service.uninstall(id: plugin.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        // Render the plugin's declarative Block Kit UI natively.
                        BlockKitView(node: plugin.ui) { service.handle($0, pluginID: plugin.id) }
                            .padding(8)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Divider()
                }
            }
        }
        .alert(item: $service.pendingInstallation) { pending in
            Alert(
                title: Text(pending.title),
                message: Text(pending.consentMessage),
                primaryButton: .cancel { service.cancelPendingInstallation() },
                secondaryButton: .default(Text("Install")) {
                    service.confirmPendingInstallation(pending)
                }
            )
        }
    }

    private func choosePackage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Install"
        if panel.runModal() == .OK, let url = panel.url {
            service.requestInstall(at: url)
        }
    }
}
