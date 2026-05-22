import SwiftUI

@main
struct AtlasApp: App {
    @StateObject private var paletteState: CommandPaletteState
    private let windowManager: AccessibilityWindowManager
    private let windowPermissionChecker = AccessibilityPermissionChecker()

    init() {
        let sharedWindowManager = AccessibilityWindowManager()
        self.windowManager = sharedWindowManager
        _paletteState = StateObject(
            wrappedValue: CommandPaletteState(windowManager: sharedWindowManager)
        )
    }

    var body: some Scene {
        MenuBarExtra("Atlas", systemImage: "square.stack.3d.up.fill") {
            ContentView(
                windowManager: windowManager,
                windowPermissionChecker: windowPermissionChecker,
                paletteState: paletteState
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            AtlasSettingsView(paletteController: paletteState.controller)
        }
    }
}

@MainActor
final class CommandPaletteState: ObservableObject {
    private(set) var controller: CommandPaletteController!
    private let hotkeyService = GlobalHotkeyService()
    private let windowManager: WindowManaging
    private let workspaceStore = WorkspaceStore()
    private let scratchpadStore = ScratchpadStore()
    let clipboardHistoryStore = ClipboardHistoryStore()
    private let scratchpadProvider: ScratchpadProvider
    private let clipboardHistoryProvider: ClipboardHistoryProvider
    private var isWindowManagementEnabled = false

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

    init(windowManager: WindowManaging = AccessibilityWindowManager()) {
        self.windowManager = windowManager
        scratchpadProvider = ScratchpadProvider(store: scratchpadStore)
        clipboardHistoryProvider = ClipboardHistoryProvider(store: clipboardHistoryStore)

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
        let snippetsProvider = SnippetsProvider()
        let customAutomationProvider = CustomAutomationProvider(
            store: CustomAutomationStore(),
            isEnabled: Self.isAutomationFeatureEnabled
        )
        let skillProvider = SkillCommandProvider()
        let appLauncherProvider = AppLauncherProvider()

        self.controller = CommandPaletteController(providers: [
            atlasProvider,
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
