import SwiftUI
import UniformTypeIdentifiers

/// 市场页:搜索 + 分类计数 chips + 已装插件卡片(MacTools 市场同构,本地语义)。
struct MarketView: View {
    @ObservedObject var service: PluginsService
    @ObservedObject var platform: PluginPlatformService

    @State private var query = ""
    @State private var selectedTrack: String?
    @State private var sourceImportStatus: String?

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

    private var filteredPlatformStatuses: [PluginStatusRecord] {
        guard selectedTrack == nil else { return [] }
        return platform.statuses.filter { $0.matchesCatalogQuery(query) }
    }

    private var installedPluginCount: Int {
        service.plugins.count + platform.statuses.count
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
                    #if !ATLAS_STORE
                    Button {
                        chooseSource()
                    } label: {
                        Label("导入 Raycast 源码…", systemImage: "hammer")
                            .font(.callout)
                    }
                    #endif
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索插件名称、别名或描述", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 6) {
                    trackChip(nil, label: "全部", count: installedPluginCount)
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
                if let sourceImportStatus {
                    Text(sourceImportStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle(
                    "Developer mode",
                    isOn: Binding(
                        get: { platform.developerModeEnabled },
                        set: { platform.setDeveloperMode(enabled: $0) }
                    )
                )
                .help("Unsigned MCP plugins run only with isolated developer authorization.")

                if let consent = platform.pendingConsent {
                    PluginConsentView(service: platform, request: consent)
                        .glassCard(padding: 10)
                }

                ForEach(filteredPlatformStatuses, id: \.pluginId) { status in
                    platformCard(status)
                }

                if filtered.isEmpty && filteredPlatformStatuses.isEmpty {
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
        let catalog = status.resolvedCatalog()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconTile(systemImage: "puzzlepiece.extension", tint: .blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(catalog.title.isEmpty ? status.pluginId : catalog.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(catalog.description.isEmpty ? "暂无描述" : catalog.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Text("版本 \(status.version)")
                        Text("·")
                        Text("更新于 \(updatedAtText(status.updatedAtUnixSeconds))")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                Spacer()
                Button("运行") {
                    platform.startDefaultCommand(pluginID: status.pluginId)
                }
            }
            DisclosureGroup("Diagnostics and recovery") {
                PluginDiagnosticsView(service: platform, status: status)
            }
        }
        .glassCard(padding: 10)
    }

    private func updatedAtText(_ unixSeconds: UInt64) -> String {
        guard unixSeconds > 0 else { return "未知" }
        return Date(timeIntervalSince1970: TimeInterval(unixSeconds))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func choosePackage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "安装"
        if panel.runModal() == .OK, let url = panel.url {
            platform.stage(packageURL: url)
        }
    }

    #if !ATLAS_STORE
    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "检查并构建"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let importer = PluginSourceImporter(builder: RustPluginSourceBuilder())
        Task {
            do {
                sourceImportStatus = try await importer.inspect(source)
                let package = try await importer.build(source)
                platform.stage(packageURL: package)
            } catch {
                sourceImportStatus = error.localizedDescription
            }
        }
    }
    #endif
}
