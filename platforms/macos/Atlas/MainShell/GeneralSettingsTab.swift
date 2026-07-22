import ServiceManagement
import SwiftUI

/// 通用 tab:MacTools 式分节设置流。
struct GeneralSettingsTab: View {
    @Binding var shellThemeRaw: String
    let paletteState: CommandPaletteState
    let onOpenCommands: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var isStyleExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                startupSection
                appearanceSection
                launcherSection
                featureSection
            }
            .padding(.vertical, 6)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 启动

    private var startupSection: some View {
        SettingsSection(title: "启动") {
            SettingsRow(
                icon: "power",
                tint: .blue,
                title: "开机时启动",
                description: launchError ?? "登录系统时自动启动 Atlas 并显示在菜单栏。"
            ) {
                Toggle("", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchError = "设置失败:\(error.localizedDescription)"
        }
    }

    // MARK: 外观

    private var appearanceSection: some View {
        SettingsSection(title: "外观") {
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(
                    icon: "paintpalette",
                    tint: .purple,
                    title: "主题",
                    description: "主窗口与菜单栏面板的整体观感,共 \(ShellThemeKind.allCases.count) 套。"
                ) { EmptyView() }
                ShellThemePickerPanel(selectionRaw: $shellThemeRaw) {}
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            SettingsRowDivider()

            SettingsRow(
                icon: "globe",
                tint: .teal,
                title: "语言",
                description: "默认跟随系统语言。"
            ) {
                Text("跟随系统 (中文)")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: 启动台

    private var launcherSection: some View {
        SettingsSection(title: "启动台") {
            SettingsRow(
                icon: "command",
                tint: .orange,
                title: "全局热键",
                description: "唤起启动台的快捷键,编辑后立即生效。"
            ) {
                KeyRecorderView { [weak controller = paletteState.controller] config in
                    controller?.updateHotkey(config)
                }
                .frame(width: 180)
            }

            SettingsRowDivider()

            SettingsRow(
                icon: "paintbrush",
                tint: .pink,
                title: "启动台样式",
                description: "背景、边框、圆角、尺寸、字体与强调色。"
            ) {
                Button(isStyleExpanded ? "收起" : "展开") {
                    withAnimation { isStyleExpanded.toggle() }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.callout)
            }

            if isStyleExpanded {
                LauncherSettingsPanel(
                    styleStore: paletteState.launcherStyleStore,
                    quicklinks: paletteState.launcherQuicklinks,
                    fallbacks: paletteState.launcherFallbacks,
                    aliases: paletteState.launcherAliases,
                    hotkeys: paletteState.launcherCommandHotkeys,
                    hotkeyConflicts: paletteState.commandHotkeyConflicts,
                    rootItems: { [weak controller = paletteState.controller] in
                        controller?.allRootItems() ?? []
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            SettingsRowDivider()

            SettingsRow(
                icon: "keyboard",
                tint: .green,
                title: "命令管理",
                description: "为启动台命令设置 Alias 与独立热键。"
            ) {
                Button("打开") { onOpenCommands() }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .font(.callout)
            }
        }
    }

    // MARK: 功能设置

    private var featureSection: some View {
        SettingsSection(title: "功能设置") {
            SettingsPanelsHost(paletteState: paletteState, includeLauncherSection: false)
                .padding(12)
        }
    }
}
