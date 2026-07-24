import AppKit
import SwiftUI

struct PluginsPanel: View {
    @ObservedObject var service: PluginsService
    @ObservedObject var platform: PluginPlatformService

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

            if let error = platform.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let consent = platform.pendingConsent {
                PluginConsentView(service: platform, request: consent)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }

            ForEach(platform.statuses, id: \.pluginId) { status in
                HStack {
                    VStack(alignment: .leading) {
                        Text(status.pluginId).font(.subheadline.weight(.semibold))
                        Text("\(status.version) · \(status.trustTier)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run") {
                        platform.startCommand(pluginID: status.pluginId, commandID: "main")
                    }
                    Button(role: .destructive) {
                        platform.uninstall(pluginID: status.pluginId)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(platform.sessions.values.sorted { $0.id < $1.id }) { session in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(session.title).font(.headline)
                        Spacer()
                        Button("Close") { platform.cancel(sessionID: session.id) }
                    }
                    DynamicPluginView(node: session.root) {
                        platform.send($0, sessionID: session.id)
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }

            if service.plugins.isEmpty {
                if platform.statuses.isEmpty {
                    Text("No plugins installed. Install an .atlasplugin package to extend Atlas.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Install"
        if panel.runModal() == .OK, let url = panel.url {
            platform.stage(packageURL: url)
        }
    }
}
