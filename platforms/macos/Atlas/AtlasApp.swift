import AppKit
import Combine
import SwiftUI

/// Where the shared content host is currently presented. Drives ContentView's
/// layout: compact popover stack vs. main-window shell (tabs + sidebar + detail).
final class ShellModeModel: ObservableObject {
    @Published var isMainWindow = false
}

/// Process-wide services, built once. Shared by the menu bar popover content and
/// the Settings scene so both drive the same palette / window / scene state.
@MainActor
final class AtlasServices {
    static let shared = AtlasServices()

    let privacyAccessLogger: PrivacyPulseAccessLogger
    let windowManager: AccessibilityWindowManager
    let windowPermissionChecker = AccessibilityPermissionChecker()
    let privacyPulseService: PrivacyPulseService
    let paletteState: CommandPaletteState
    let shellMode = ShellModeModel()
    /// Single hosting controller that migrates between the popover and the main
    /// window, so the 60+ module services and their state exist once per process.
    private(set) lazy var contentHost = NSHostingController(rootView: makeContentView())
    var openMainWindow: (() -> Void)?

    private init() {
        let logger = PrivacyPulseAccessLogger()
        PrivacyPulseReporter.shared.logger = logger
        let sharedWindowManager = AccessibilityWindowManager(accessLogger: logger)
        privacyAccessLogger = logger
        windowManager = sharedWindowManager
        privacyPulseService = PrivacyPulseService(
            statusProvider: PrivacyPulseSystemStatusProvider(accessLogger: logger),
            eventStore: logger
        )
        AtlasBridge.captureService = AtlasCaptureService.logging(base: .live, accessLogger: logger)
        AtlasBridge.windowCaptureProvider = LoggingWindowCaptureProvider(accessLogger: logger)
        paletteState = CommandPaletteState(windowManager: sharedWindowManager, accessLogger: logger)
    }

    func makeContentView() -> ContentView {
        ContentView(
            windowManager: windowManager,
            windowPermissionChecker: windowPermissionChecker,
            paletteState: paletteState,
            privacyPulseService: privacyPulseService,
            privacyAccessLogger: privacyAccessLogger,
            shellMode: shellMode
        )
    }
}

@main
struct AtlasApp: App {
    @NSApplicationDelegateAdaptor(AtlasAppDelegate.self) private var appDelegate

    var body: some Scene {
        // 旧独立设置窗已废弃:Settings scene 只做重定向 —— 系统 ⌘, 一触发
        // 就关掉自己并打开主界面(设置在通用 tab)。
        Settings {
            SettingsRedirectView()
        }
    }
}

/// Settings scene 占位:出现即转跳主窗口并自我关闭。
private struct SettingsRedirectView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                AtlasServices.shared.openMainWindow?()
                DispatchQueue.main.async {
                    for window in NSApp.windows
                    where window.contentViewController is NSHostingController<SettingsRedirectView> {
                        window.close()
                    }
                    // SwiftUI settings window content is wrapped; fallback: close by title.
                    for window in NSApp.windows where window.title.contains("Settings") || window.title.contains("设置") {
                        if window.frameAutosaveName != "AtlasMainWindow" {
                            window.close()
                        }
                    }
                }
            }
    }
}

@MainActor
final class AtlasAppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = AtlasMenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()
        // SwiftUI 稍后可能重建主菜单(Settings scene),下一拍再夺回。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.mainMenu = self.makeMainMenu()
        }
        menuBar.install()
        DockIconStore.shared.apply()
        // Dev/automation affordance: `open Atlas.app --args --main-window`.
        if ProcessInfo.processInfo.arguments.contains("--main-window") {
            DispatchQueue.main.async {
                AtlasServices.shared.openMainWindow?()
            }
        }
    }
}

extension AtlasAppDelegate {
    /// 系统菜单栏(主窗口打开、app 前台时可见):Atlas 应用菜单 + 编辑菜单。
    /// ⌘, 打开主界面(设置在通用 tab)、⌘Q 退出;编辑菜单让文本框的 ⌘C/⌘V/⌘A 生效。
    @objc func openMainWindowFromMenu() {
        AtlasServices.shared.openMainWindow?()
    }

    func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Atlas")
        appMenuItem.submenu = appMenu

        let about = NSMenuItem(
            title: loc("关于 Atlas", "About Atlas"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settings = NSMenuItem(
            title: loc("设置…", "Settings…"),
            action: #selector(openMainWindowFromMenu),
            keyEquivalent: ","
        )
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        let hide = NSMenuItem(title: loc("隐藏 Atlas", "Hide Atlas"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hide)
        appMenu.addItem(.separator())

        let quit = NSMenuItem(
            title: loc("退出 Atlas", "Quit Atlas"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quit)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: loc("编辑", "Edit"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: loc("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: loc("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: loc("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: loc("复制", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: loc("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: loc("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        return mainMenu
    }
}

/// Owns the menu bar status item. Left-click toggles the Atlas panel popover;
/// right-click (or control-click) opens a quick-actions menu of common commands.
@MainActor
final class AtlasMenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let mainWindow = AtlasMainWindowController()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = MenuBarIconStore.shared.statusImage()
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Atlas"
            button.target = self
            button.action = #selector(statusButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        MenuBarIconStore.shared.applyHandler = { [weak self] in
            self?.statusItem?.button?.image = MenuBarIconStore.shared.statusImage()
        }

        popover.behavior = .transient
        popover.animates = true
        // Explicit size: self-sizing SwiftUI content otherwise leaves the popover
        // with a zero/ambiguous size and it never appears.
        popover.contentSize = NSSize(width: 460, height: 560)
        popover.contentViewController = AtlasServices.shared.contentHost
        popover.delegate = self
        mainWindow.popover = popover
        AtlasServices.shared.openMainWindow = { [weak self] in
            self?.mainWindow.show()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverDismissMonitors()
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showQuickMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    /// Lightweight popover host used while the main window owns the shared
    /// ContentView host — the menu bar panel stays clickable in parallel.
    private lazy var standalonePanelHost = NSHostingController(rootView: StandaloneMenuPanelView())
    private var popoverDismissMonitors: [Any] = []

    /// transient 行为在自家窗口前台时不可靠:显式监听,点到面板外一律收起。
    private func installPopoverDismissMonitors() {
        removePopoverDismissMonitors()
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.window != self.popover.contentViewController?.view.window {
                self.popover.performClose(nil)
            }
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }
        popoverDismissMonitors = [local, global].compactMap { $0 }
    }

    private func removePopoverDismissMonitors() {
        popoverDismissMonitors.forEach { NSEvent.removeMonitor($0) }
        popoverDismissMonitors = []
    }

    private func togglePopover(from sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        if mainWindow.isVisible {
            popover.contentViewController = standalonePanelHost
        } else if popover.contentViewController == nil || popover.contentViewController === standalonePanelHost {
            popover.contentViewController = AtlasServices.shared.contentHost
        }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        installPopoverDismissMonitors()
    }

    private func showQuickMenu(from sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil) }

        let entries: [QuickMenuPanelController.Entry] = [
            .init(id: "open", icon: "square.grid.2x2", title: loc("打开 Atlas", "Open Atlas"), shortcutHint: nil) { [weak self] in
                self?.openPanelAction()
            },
            .init(id: "main", icon: "macwindow", title: loc("打开主窗口", "Open Main Window"), shortcutHint: nil) { [weak self] in
                self?.mainWindow.show()
            },
            .init(id: "palette", icon: "sparkles", title: loc("命令面板", "Command Palette"), shortcutHint: nil) {
                AtlasServices.shared.paletteState.controller.show()
            },
            .init(id: "prefs", icon: "gearshape", title: loc("偏好设置…", "Preferences…"), shortcutHint: "⌘,") {
                AtlasServices.shared.openMainWindow?()
            },
            .init(id: "about", icon: "info.circle", title: loc("关于 Atlas", "About Atlas"), shortcutHint: nil) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            },
            .init(id: "quit", icon: "power", title: loc("退出 Atlas", "Quit Atlas"), shortcutHint: "⌘Q") {
                NSApp.terminate(nil)
            },
        ]

        QuickMenuPanelController.shared.toggle(
            from: sender,
            entries: entries,
            delayedCapture: { seconds in ScreenshotActions.captureRegionDelayed(seconds: seconds) }
        )
    }

    private func openPanelAction() {
        guard let button = statusItem?.button else { return }
        togglePopover(from: button)
    }

    @objc private func openPanel() {
        guard let button = statusItem?.button else { return }
        togglePopover(from: button)
    }

    @objc private func openMainWindow() {
        mainWindow.show()
    }

    @objc private func delayedCapture(_ sender: NSMenuItem) {
        ScreenshotActions.captureRegionDelayed(seconds: sender.tag)
    }

    @objc private func openPalette() {
        AtlasServices.shared.paletteState.controller.show()
    }

    @objc private func openPreferences() {
        AtlasServices.shared.openMainWindow?()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

/// Hosts the shared ContentView in a standard resizable main window. The single
/// NSHostingController migrates between the popover and this window so all
/// module services and state stay in one live view tree; `ShellModeModel`
/// switches ContentView between the compact popover layout and the shell
/// layout (category tabs + tool sidebar + detail).
@MainActor
final class AtlasMainWindowController: NSObject, NSWindowDelegate {
    weak var popover: NSPopover?
    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        let services = AtlasServices.shared
        if popover?.isShown == true {
            popover?.performClose(nil)
        }

        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            created.title = "Atlas"
            // Aurora theme: content (background bands) extends under a
            // transparent titlebar for a seamless glass look.
            created.titlebarAppearsTransparent = true
            created.titleVisibility = .hidden
            // 背景拖动会吞掉 Slider/ColorPicker 的轨道拖拽,关闭;标题栏仍可拖动窗口。
            created.isMovableByWindowBackground = false
            created.isReleasedWhenClosed = false
            created.center()
            created.setFrameAutosaveName("AtlasMainWindow")
            created.delegate = self
            window = created
        }

        if window?.contentViewController !== services.contentHost {
            popover?.contentViewController = nil
            services.shellMode.isMainWindow = true
            window?.contentViewController = services.contentHost
        }

        NSApp.setActivationPolicy(.regular)
        // Accessory→regular 切换会重置 Dock 图标,这里重新套用预设。
        DockIconStore.shared.apply()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func focus() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        let services = AtlasServices.shared
        window?.contentViewController = nil
        services.shellMode.isMainWindow = false
        popover?.contentViewController = services.contentHost
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class CommandPaletteState: ObservableObject {
    private(set) var controller: LauncherPanelController!
    let launcherStyleStore = LauncherStyleStore()
    let launcherFavorites = FavoritesStore()
    let launcherAliases = AliasStore()
    let launcherCommandHotkeys = CommandHotkeyStore()
    let launcherQuicklinks = QuicklinkStore()
    let launcherFallbacks = FallbackStore()
    @Published private(set) var commandHotkeyConflicts: [String: String] = [:]
    private var registeredCommandHotkeys: [String: HotkeyConfig] = [:]
    private var commandHotkeyObservation: AnyCancellable?
    private let hotkeyService: GlobalHotkeyService
    private let windowManager: WindowManaging
    private let workspaceStore = WorkspaceStore()
    private let scratchpadStore = ScratchpadStore()
    let sceneCoordinator = SceneCoordinator()
    let audioHubService = AudioHubService()
    let bluetoothQuickActionsService = BluetoothQuickActionsService()
    let flowInboxStore = FlowInboxStore()
    let clipboardHistoryStore = ClipboardHistoryStore()
    private let scratchpadProvider: ScratchpadProvider
    private let clipboardHistoryProvider: ClipboardHistoryProvider
    private var isWindowManagementEnabled = false
    private var isAudioHubEnabled = false
    private var isFlowInboxEnabled = false
    private var isSceneSystemEnabled = false

    var sharedScratchpadStore: ScratchpadStore {
        scratchpadStore
    }

    // Callbacks that redirect to ContentView's actual methods at runtime
    private var onCaptureDesktop: (() -> Void)?
    private var onCaptureArea: (() -> Void)?
    private var onCaptureWindow: (() -> Void)?
    private var onSaveCurrentWorkspace: (() -> Void)?
    private var onRestoreWorkspace: ((Workspace) -> Void)?
    private var isSystemUtilitiesEnabled: (() -> Bool)?
    private var onToggleKeepAwake: (() -> Void)?
    private var onTogglePresentationMode: (() -> Void)?
    private var onOpenHandMirror: (() -> Void)?
    private var onRefreshDisplays: (() -> Void)?

    init(
        windowManager: WindowManaging = AccessibilityWindowManager(),
        accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
    ) {
        self.windowManager = windowManager
        self.hotkeyService = GlobalHotkeyService(accessLogger: accessLogger)
        scratchpadProvider = ScratchpadProvider(store: scratchpadStore)
        clipboardHistoryProvider = ClipboardHistoryProvider(
            store: clipboardHistoryStore,
            accessLogger: accessLogger
        )

        let atlasProvider = AtlasCommandProvider(
            onCaptureDesktop: { [weak self] in self?.onCaptureDesktop?() },
            onCaptureArea: { [weak self] in self?.onCaptureArea?() },
            onCaptureWindow: { [weak self] in self?.onCaptureWindow?() },
            onOpenSettings: {
                AtlasServices.shared.openMainWindow?()
            }
        )
        let developerToolsProvider = DeveloperToolsProvider()
        let windowManagementProvider = WindowManagementProvider(
            windowManager: windowManager,
            isEnabled: { [weak self] in self?.isWindowManagementEnabled == true }
        )
        let systemUtilitiesProvider = SystemUtilitiesProvider(
            isEnabled: { [weak self] in self?.isSystemUtilitiesEnabled?() ?? false },
            onToggleKeepAwake: { [weak self] in self?.onToggleKeepAwake?() },
            onTogglePresentationMode: { [weak self] in self?.onTogglePresentationMode?() },
            onOpenHandMirror: { [weak self] in self?.onOpenHandMirror?() },
            onRefreshDisplays: { [weak self] in self?.onRefreshDisplays?() }
        )
        let tokenBarProvider = TokenBarCommandProvider(
            isEnabled: Self.isTokenBarFeatureEnabled,
            onOpenSettings: {
                AtlasServices.shared.openMainWindow?()
            },
            importer: TokenBarProviderUsageImporter(),
            onRefreshSummary: { summary in
                NotificationCenter.default.post(name: .tokenBarSummaryDidChange, object: summary)
            },
            onShowStatus: { message, kind in
                NotificationCenter.default.post(
                    name: .tokenBarCommandStatusDidChange,
                    object: TokenBarCommandStatus(message: message, kind: kind)
                )
            }
        )
        let workspaceProvider = WorkspaceProvider(
            store: workspaceStore,
            isEnabled: { [weak self] in self?.isWindowManagementEnabled == true },
            onSaveCurrent: { [weak self] in self?.onSaveCurrentWorkspace?() },
            onRestore: { [weak self] workspace in self?.onRestoreWorkspace?(workspace) }
        )
        let snippetsProvider = SnippetsProvider(accessLogger: accessLogger)
        let customAutomationProvider = CustomAutomationProvider(
            store: CustomAutomationStore(),
            isEnabled: Self.isAutomationFeatureEnabled
        )
        let skillProvider = SkillCommandProvider()
        let appLauncherProvider = AppLauncherProvider()
        let sceneProvider = SceneCommandProvider(
            coordinator: sceneCoordinator,
            isEnabled: { [weak self] in self?.isSceneSystemEnabled == true }
        )
        let audioHubProvider = AudioHubCommandProvider(
            service: audioHubService,
            isEnabled: { [weak self] in self?.isAudioHubEnabled == true }
        )
        let flowInboxProvider = FlowInboxCommandProvider(
            isEnabled: { [weak self] in self?.isFlowInboxEnabled == true }
        )
        let calculatorProvider = CalculatorCommandProvider()
        let identifierProvider = IdentifierProvider()
        let passwordProvider = PasswordGeneratorProvider()
        let hashProvider = HashGeneratorProvider()
        let encodingProvider = EncodingProvider()
        let jsonProvider = JSONFormatProvider()
        let loremProvider = LoremIpsumProvider()
        let colorFormatProvider = ColorFormatProvider()
        let regexProvider = RegexTesterProvider()
        let timezoneProvider = TimezoneProvider()
        let emojiProvider = EmojiProvider()
        let fileSearchProvider = FileSearchProvider()
        let bookmarkProvider = BookmarkProvider()
        let shellScriptProvider = ShellScriptProvider()

        let providers: [CommandProviding] = [
            calculatorProvider,
            identifierProvider,
            passwordProvider,
            hashProvider,
            encodingProvider,
            jsonProvider,
            loremProvider,
            colorFormatProvider,
            regexProvider,
            timezoneProvider,
            emojiProvider,
            fileSearchProvider,
            bookmarkProvider,
            shellScriptProvider,
            atlasProvider,
            sceneProvider,
            audioHubProvider,
            flowInboxProvider,
            tokenBarProvider,
            developerToolsProvider,
            windowManagementProvider,
            systemUtilitiesProvider,
            workspaceProvider,
            clipboardHistoryProvider,
            snippetsProvider,
            scratchpadProvider,
            customAutomationProvider,
            skillProvider,
            appLauncherProvider,
        ]

        var sources: [LauncherItemSource] = providers.map {
            CommandProviderAdapter(provider: $0, sourceID: String(describing: type(of: $0)))
        }
        sources.append(ClosureItemSource(sourceID: "quicklinks") { [launcherQuicklinks] query in
            launcherQuicklinks.makeItems(query: query)
        })
        sources.append(EmojiGridSource())
        sources.append(MenuBarItemSource())

        self.controller = LauncherPanelController(
            sources: sources,
            styleStore: launcherStyleStore,
            favorites: launcherFavorites
        )
        self.controller.aliasResolver = launcherAliases
        self.controller.fallbackItemsProvider = { [launcherFallbacks] query in
            launcherFallbacks.makeItems(query: query)
        }

        self.controller.skillRunViewBuilder = { skill in
            AnyView(SkillPanel(skill: skill, runner: SkillRuntimeFactory.makeDefaultRunner()))
        }

        // Wire hotkey updates dynamically
        self.controller.onHotkeyChanged = { [weak self] newConfig in
            self?.registerHotkey(newConfig)
        }

        // Load initial hotkey configuration and start
        let config = HotkeyConfig.load()
        registerHotkey(config)
        registerCommandHotkeys()
        commandHotkeyObservation = launcherCommandHotkeys.$hotkeys
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.registerCommandHotkeys() }
            }
        hotkeyService.start()
    }

    /// Registers per-command global hotkeys; conflicts with the main palette
    /// hotkey or between commands are reported instead of registered.
    private func registerCommandHotkeys() {
        // 每命令热键暂时下线(命令页已隐藏该列);清掉历史注册,避免不可见的按键占用。
        for (_, previous) in registeredCommandHotkeys {
            hotkeyService.unregister(
                keyCode: previous.keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: previous.modifiers)
            )
        }
        registeredCommandHotkeys = [:]
        commandHotkeyConflicts = [:]
        return
    }

    private func registerCommandHotkeysDisabled() {
        for (_, previous) in registeredCommandHotkeys {
            hotkeyService.unregister(
                keyCode: previous.keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: previous.modifiers)
            )
        }
        registeredCommandHotkeys = [:]

        var conflicts: [String: String] = [:]
        let main = HotkeyConfig.load()
        var claimed: [String: String] = [:] // "keyCode|modifiers" → commandKey

        for (commandKey, hotkey) in launcherCommandHotkeys.hotkeys.sorted(by: { $0.key < $1.key }) {
            let signature = "\(hotkey.keyCode)|\(hotkey.modifiers)"
            if hotkey.keyCode == main.keyCode && hotkey.modifiers == main.modifiers {
                conflicts[commandKey] = "Conflicts with the launcher hotkey"
                continue
            }
            if let existing = claimed[signature] {
                conflicts[commandKey] = "Conflicts with \(existing)"
                continue
            }
            claimed[signature] = commandKey
            registeredCommandHotkeys[commandKey] = hotkey
            let flags = NSEvent.ModifierFlags(rawValue: hotkey.modifiers)
            hotkeyService.register(keyCode: hotkey.keyCode, modifiers: flags) { [weak self] in
                self?.controller?.execute(commandKey: commandKey)
            }
        }
        commandHotkeyConflicts = conflicts
    }

    func setActions(
        onCaptureDesktop: @escaping () -> Void,
        onCaptureArea: @escaping () -> Void,
        onCaptureWindow: @escaping () -> Void,
        isSystemUtilitiesEnabled: @escaping () -> Bool,
        onToggleKeepAwake: @escaping () -> Void,
        onTogglePresentationMode: @escaping () -> Void,
        onOpenHandMirror: @escaping () -> Void,
        onRefreshDisplays: @escaping () -> Void
    ) {
        self.onCaptureDesktop = onCaptureDesktop
        self.onCaptureArea = onCaptureArea
        self.onCaptureWindow = onCaptureWindow
        self.isSystemUtilitiesEnabled = isSystemUtilitiesEnabled
        self.onToggleKeepAwake = onToggleKeepAwake
        self.onTogglePresentationMode = onTogglePresentationMode
        self.onOpenHandMirror = onOpenHandMirror
        self.onRefreshDisplays = onRefreshDisplays
    }

    func setWindowManagementEnabled(_ enabled: Bool) {
        isWindowManagementEnabled = enabled
    }

    func setAudioHubEnabled(_ enabled: Bool) {
        isAudioHubEnabled = enabled
        if enabled {
            audioHubService.refresh()
            bluetoothQuickActionsService.refresh()
        }
    }

    func setFlowInboxEnabled(_ enabled: Bool) {
        isFlowInboxEnabled = enabled
    }

    func setSceneSystemEnabled(_ enabled: Bool) {
        isSceneSystemEnabled = enabled
        if enabled {
            sceneCoordinator.start()
        } else {
            sceneCoordinator.stop()
        }
    }

    func setScratchpadEnabled(_ enabled: Bool) {
        scratchpadProvider.setEnabled(enabled)
    }

    func setClipboardHistoryEnabled(_ enabled: Bool) {
        clipboardHistoryProvider.setEnabled(enabled)
    }

    func setClipboardHistoryChangedHandler(_ handler: @escaping () -> Void) {
        clipboardHistoryProvider.setHistoryChangedHandler(handler)
    }

    func setWorkspaceActions(
        onSaveCurrent: @escaping () -> Void,
        onRestore: @escaping (Workspace) -> Void
    ) {
        onSaveCurrentWorkspace = onSaveCurrent
        onRestoreWorkspace = onRestore
    }

    private func registerHotkey(_ config: HotkeyConfig) {
        let flags = NSEvent.ModifierFlags(rawValue: config.modifiers)
        hotkeyService.register(keyCode: config.keyCode, modifiers: flags) { [weak self] in
            self?.controller?.toggle()
        }
    }

    private static func isAutomationFeatureEnabled() -> Bool {
        isFeatureEnabled(AtlasModule.automation.featureName)
    }

    private static func isTokenBarFeatureEnabled() -> Bool {
        isFeatureEnabled(AtlasModule.tokenbar.featureName)
    }

    private static func isFeatureEnabled(_ featureName: String) -> Bool {
        guard let features = try? AtlasBridge.listFeatures() else {
            return false
        }

        for feature in features {
            if feature.name == featureName {
                return feature.isEnabled
            }
        }

        return false
    }
}
