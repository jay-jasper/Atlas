import SwiftUI
import UniformTypeIdentifiers

/// 市场页:搜索 + 分类计数 chips + 已装插件卡片(MacTools 市场同构,本地语义)。
struct MarketView: View {
    @ObservedObject var service: PluginsService
    @StateObject private var platform = PluginPlatformService()

    @State private var query = ""
    @State private var selectedTrack: String?

    private var tracks: [(name: String, count: Int)] {
        Dictionary(grouping: service.plugins, by: \.track)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name < $1.name }
    }

    private var filtered: [PluginDescriptor] {
        service.plugins.filter { plugin in
            (selectedTrack == nil || plugin.track == selectedTrack)
                && (query.isEmpty || plugin.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("市场")
                            .font(.title3.weight(.semibold))
                        Text("安装、管理 WASM / MCP / JS 插件。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        service.refresh()
                        platform.refreshStatuses()
                    } label: {
                        Label("刷新列表", systemImage: "arrow.clockwise")
                            .font(.callout)
                    }
                    Button {
                        choosePackage()
                    } label: {
                        Label("安装包…", systemImage: "square.and.arrow.down")
                            .font(.callout)
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索插件名称", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 6) {
                    trackChip(nil, label: "全部", count: service.plugins.count)
                    ForEach(tracks, id: \.name) { track in
                        trackChip(track.name, label: track.name.uppercased(), count: track.count)
                    }
                }

                if !service.statusMessage.isEmpty {
                    Text(service.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = platform.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if let consent = platform.pendingConsent {
                    PluginConsentView(service: platform, request: consent)
                        .glassCard(padding: 10)
                }

                ForEach(platform.statuses, id: \.pluginId) { status in
                    platformCard(status)
                }

                ForEach(platform.sessions.values.sorted { $0.id < $1.id }) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(session.title).font(.headline)
                            Spacer()
                            Button("关闭") { platform.cancel(sessionID: session.id) }
                        }
                        DynamicPluginView(node: session.root) {
                            platform.send($0, sessionID: session.id)
                        }
                    }
                    .glassCard(padding: 10)
                }

                if filtered.isEmpty && platform.statuses.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 34))
                            .foregroundColor(.secondary)
                        Text(service.plugins.isEmpty ? "还没有安装插件,点击「安装包…」添加。" : "没有匹配的插件。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(filtered) { plugin in
                        pluginCard(plugin)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .alert(item: $service.pendingInstallation) { pending in
            Alert(
                title: Text(pending.title),
                message: Text(pending.consentMessage),
                primaryButton: .cancel { service.cancelPendingInstallation() },
                secondaryButton: .default(Text("安装")) {
                    service.confirmPendingInstallation(pending)
                }
            )
        }
    }

    private func trackChip(_ track: String?, label: String, count: Int) -> some View {
        Button {
            selectedTrack = track
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.caption)
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .background(Color.primary.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    selectedTrack == track
                        ? Color.accentColor.opacity(0.2)
                        : Color.primary.opacity(0.05)
                )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func pluginCard(_ plugin: PluginDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconTile(systemImage: "puzzlepiece.extension", tint: .blue)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(plugin.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(plugin.version)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(plugin.track.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    service.uninstall(id: plugin.id)
                } label: {
                    Text("卸载")
                        .font(.caption)
                }
            }

            BlockKitView(node: plugin.ui) { service.handle($0, pluginID: plugin.id) }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .glassCard(padding: 10)
    }

    private func platformCard(_ status: PluginStatusRecord) -> some View {
        HStack(spacing: 10) {
            IconTile(systemImage: "puzzlepiece.extension", tint: .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.pluginId).font(.system(size: 13, weight: .semibold))
                Text("\(status.version) · \(status.trustTier)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button("运行") {
                platform.startCommand(pluginID: status.pluginId, commandID: "main")
            }
            Button("卸载", role: .destructive) {
                platform.uninstall(pluginID: status.pluginId)
            }
        }
        .glassCard(padding: 10)
    }

    private func choosePackage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "安装"
        if panel.runModal() == .OK, let url = panel.url {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                service.requestInstall(at: url)
            } else {
                platform.stage(packageURL: url)
            }
        }
    }
}
