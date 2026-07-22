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
        Settings {
            AtlasSettingsView(paletteState: AtlasServices.shared.paletteState)
        }
    }
}

@MainActor
final class AtlasAppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = AtlasMenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBar.install()
        // Dev/automation affordance: `open Atlas.app --args --main-window`.
        if ProcessInfo.processInfo.arguments.contains("--main-window") {
            DispatchQueue.main.async {
                AtlasServices.shared.openMainWindow?()
            }
        }
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
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Atlas"
            button.target = self
            button.action = #selector(statusButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

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
    }

    private func showQuickMenu(from sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil) }

        let menu = NSMenu()
        menu.addItem(menuItem("打开 Atlas", #selector(openPanel)))
        menu.addItem(menuItem("打开主窗口", #selector(openMainWindow)))

        let palette = menuItem("命令面板", #selector(openPalette), key: "k")
        palette.keyEquivalentModifierMask = [.command]
        menu.addItem(palette)

        let delayItem = NSMenuItem(title: "延时截图", action: nil, keyEquivalent: "")
        let delayMenu = NSMenu()
        for seconds in [3, 5, 10] {
            let item = NSMenuItem(title: "\(seconds) 秒后截图", action: #selector(delayedCapture(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            delayMenu.addItem(item)
        }
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        menu.addItem(.separator())

        let prefs = menuItem("偏好设置…", #selector(openPreferences), key: ",")
        prefs.keyEquivalentModifierMask = [.command]
        menu.addItem(prefs)
        menu.addItem(menuItem("关于 Atlas", #selector(showAbout)))

        menu.addItem(.separator())

        let quit = menuItem("退出 Atlas", #selector(quitApp), key: "q")
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
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
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
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
            // Unified toolbar style: taller titlebar so traffic lights sit
            // lower, aligned with the tab bar row.
            created.toolbarStyle = .unified
            let toolbar = NSToolbar(identifier: "AtlasMainToolbar")
            toolbar.showsBaselineSeparator = false
            created.toolbar = toolbar
            created.isMovableByWindowBackground = true
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
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
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
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
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
