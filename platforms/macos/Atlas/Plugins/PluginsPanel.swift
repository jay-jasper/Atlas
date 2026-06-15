import SwiftUI

struct PluginsPanel: View {
    @ObservedObject var service: PluginsService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Plugins", systemImage: "puzzlepiece.extension")
                .font(.headline)

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
                        BlockKitView(node: plugin.ui) { service.handle($0) }
                            .padding(8)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Divider()
                }
            }
        }
    }
}
