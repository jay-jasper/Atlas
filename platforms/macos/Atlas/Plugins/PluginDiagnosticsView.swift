import AppKit
import SwiftUI

struct PluginDiagnosticsView: View {
    @ObservedObject var service: PluginPlatformService
    let status: PluginStatusRecord
    @State private var diagnosticsJSON = ""
    @State private var clearDataOnRollback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(status.pluginId).font(.headline)
                    Text("\(status.version) · \(status.publisher) · \(status.trustTier)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if status.observingUpdate {
                    Label("Observing update", systemImage: "waveform.path.ecg")
                        .font(.caption)
                }
            }

            LabeledContent("Package root", value: status.packageRoot)
                .font(.caption.monospaced())
            Text("Granted: \(status.grantedCapabilities.joined(separator: ", "))")
                .font(.caption)
            if !status.deniedCapabilities.isEmpty {
                Text("Denied: \(status.deniedCapabilities.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button("Stop") { service.stop(pluginID: status.pluginId) }
                Button("Restart") { service.restart(pluginID: status.pluginId) }
                Button("Re-enable main") {
                    service.resetCommandBreaker(pluginID: status.pluginId, commandID: "main")
                }
                Button("Revoke grants") {
                    service.replaceGrants(pluginID: status.pluginId, grants: [])
                }
            }

            HStack {
                Toggle("Clear incompatible data", isOn: $clearDataOnRollback)
                Button("Rollback") {
                    service.rollback(
                        pluginID: status.pluginId,
                        clearData: clearDataOnRollback
                    )
                }
                Button("Clear data", role: .destructive) {
                    service.clearData(pluginID: status.pluginId)
                }
                Button("Uninstall", role: .destructive) {
                    service.uninstall(pluginID: status.pluginId)
                }
            }

            HStack {
                Button("Refresh diagnostics") { refreshDiagnostics() }
                Button("Export…") { exportDiagnostics() }
                    .disabled(diagnosticsJSON.isEmpty)
            }
            if !diagnosticsJSON.isEmpty {
                ScrollView {
                    Text(diagnosticsJSON)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
        }
        .padding()
        .onAppear(perform: refreshDiagnostics)
    }

    private func refreshDiagnostics() {
        diagnosticsJSON = service.diagnostics(pluginID: status.pluginId)?.json ?? ""
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(status.pluginId)-diagnostics.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(diagnosticsJSON.utf8).write(to: url, options: .atomic)
    }
}

struct DeveloperModeSettingsView: View {
    @ObservedObject var settings: DeveloperModeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Developer mode", isOn: $settings.enabled)
            Text("Unsigned MCP plugins require isolated path, command, and network authorization. Turning this off terminates them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = settings.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
