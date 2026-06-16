import AppKit
import SwiftUI

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
            privacyAccessLogger: privacyAccessLogger
        )
    }
}

@main
struct AtlasApp: App {
    var body: some Scene {
        // Show the main program in a normal window on launch (menu bar set aside
        // for now). The same ContentView the popover hosted.
        Window("Atlas", id: "atlas-main") {
            AtlasMainView()
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 760, height: 560)

        Settings {
            AtlasSettingsView(paletteController: AtlasServices.shared.paletteState.controller)
        }
    }
}

@MainActor
final class AtlasAppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = AtlasMenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.install()
    }
}

/// Owns the menu bar status item. Left-click toggles the Atlas panel popover;
/// right-click (or control-click) opens a quick-actions menu of common commands.
@MainActor
final class AtlasMenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

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
        let host = NSHostingController(rootView: AtlasServices.shared.makeContentView())
        popover.contentViewController = host
        popover.delegate = self
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

    private func togglePopover(from sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showQuickMenu(from sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil) }

        let menu = NSMenu()
        menu.addItem(menuItem("打开 Atlas", #selector(openPanel)))

        let palette = menuItem("命令面板", #selector(openPalette), key: "k")
        palette.keyEquivalentModifierMask = [.command]
        menu.addItem(palette)

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

@MainActor
final class CommandPaletteState: ObservableObject {
    private(set) var controller: CommandPaletteController!
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

        self.controller = CommandPaletteController(providers: [
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
        ])

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
        hotkeyService.start()
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
