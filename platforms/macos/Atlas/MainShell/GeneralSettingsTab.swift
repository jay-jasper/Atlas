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
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.system.rawValue
    @State private var languageChanged = false
    @ObservedObject private var menuBarIcon = MenuBarIconStore.shared
    @ObservedObject private var dockIcon = DockIconStore.shared

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
        SettingsSection(title: loc("启动", "Startup")) {
            SettingsRow(
                icon: "power",
                tint: .blue,
                title: loc("开机时启动", "Launch at Login"),
                description: launchError ?? loc("登录系统时自动启动 Atlas 并显示在菜单栏。", "Start Atlas automatically at login and show it in the menu bar.")
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
        SettingsSection(title: loc("外观", "Appearance")) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(
                    icon: "paintpalette",
                    tint: .purple,
                    title: loc("主题", "Theme"),
                    description: "主窗口与菜单栏面板的整体观感,共 \(ShellThemeKind.allCases.count) 套。"
                ) { EmptyView() }
                ShellThemePickerPanel(selectionRaw: $shellThemeRaw, onSelect: {}, fixedWidth: false)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            SettingsRowDivider()

            SettingsRow(
                icon: "globe",
                tint: .teal,
                title: loc("语言", "Language"),
                description: languageChanged
                    ? loc("语言已修改,重启应用后生效。", "Language changed — relaunch to apply.")
                    : loc("默认跟随系统语言,先支持中文与英文。", "Follows the system by default. Chinese and English for now.")
            ) {
                HStack(spacing: 8) {
                    Picker("", selection: $languageRaw) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .onChange(of: languageRaw) { _ in
                        languageChanged = languageRaw != AppLanguage.current.rawValue
                    }
                    if languageChanged {
                        Button(loc("立即重启", "Relaunch")) { Self.relaunch() }
                            .font(.callout)
                    }
                }
            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 6) {
                SettingsRow(
                    icon: "menubar.rectangle",
                    tint: .cyan,
                    title: loc("菜单栏图标", "Menu Bar Icon"),
                    description: menuBarIcon.hasCustomIcon
                        ? loc("使用自定义图标。", "Using a custom icon.")
                        : loc("选择内置图标,或上传本地图片。", "Pick a built-in icon or upload an image.")
                ) {
                    HStack(spacing: 8) {
                        if menuBarIcon.hasCustomIcon {
                            Button(loc("恢复默认", "Restore Default")) {
                                menuBarIcon.restoreDefault()
                            }
                            .font(.callout)
                        }
                        Button(loc("上传", "Upload")) { pickMenuBarIcon() }
                            .font(.callout)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }

                HStack(spacing: 8) {
                    Text(loc("图标来源", "Presets"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(MenuBarIconStore.presets, id: \.id) { preset in
                        Button {
                            menuBarIcon.selectPreset(preset.id)
                        } label: {
                            Image(systemName: preset.symbol)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 30, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6).fill(
                                        menuBarIcon.presetID == preset.id
                                            ? Color.accentColor.opacity(0.22)
                                            : Color.primary.opacity(0.05)
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6).stroke(
                                        menuBarIcon.presetID == preset.id
                                            ? Color.accentColor
                                            : Color.primary.opacity(0.1),
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help(preset.name)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 6) {
                SettingsRow(
                    icon: "dock.rectangle",
                    tint: .indigo,
                    title: loc("Dock 图标", "Dock Icon"),
                    description: loc("9 款预设,主窗口打开时生效于 Dock。", "9 presets, shown in the Dock while the main window is open.")
                ) {
                    if dockIcon.presetID != nil {
                        Button(loc("恢复默认", "Restore Default")) {
                            dockIcon.select(nil)
                        }
                        .font(.callout)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 9), spacing: 8) {
                    ForEach(DockIconStore.presets) { preset in
                        Button {
                            dockIcon.select(preset.id)
                        } label: {
                            Image(nsImage: DockIconStore.render(preset, size: 64))
                                .resizable()
                                .frame(width: 44, height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10).stroke(
                                        dockIcon.presetID == preset.id ? Color.accentColor : Color.clear,
                                        lineWidth: 2
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help(preset.name)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    private func pickMenuBarIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic, .icns]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !menuBarIcon.setCustomIcon(from: url) {
                launchError = loc("图片无法读取", "Could not load the image")
            }
        }
    }

    private static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundleURL.path]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    // MARK: 启动台

    private var launcherSection: some View {
        SettingsSection(title: loc("启动台", "Launcher")) {
            SettingsRow(
                icon: "command",
                tint: .orange,
                title: loc("全局热键", "Global Hotkey"),
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
                title: loc("启动台样式", "Launcher Style"),
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
                title: loc("命令管理", "Commands"),
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
        SettingsSection(title: loc("功能设置", "Features")) {
            SettingsPanelsHost(paletteState: paletteState, includeLauncherSection: false)
                .padding(12)
        }
    }
}
