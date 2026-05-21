import SwiftUI

@main
struct AtlasApp: App {
    @StateObject private var paletteState = CommandPaletteState()

    var body: some Scene {
        MenuBarExtra("Atlas", systemImage: "square.stack.3d.up.fill") {
            ContentView(paletteState: paletteState)
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

    // Callbacks that redirect to ContentView's actual methods at runtime
    private var onCaptureDesktop: (() -> Void)?
    private var onCaptureArea: (() -> Void)?
    private var onCaptureWindow: (() -> Void)?

    init() {
        let atlasProvider = AtlasCommandProvider(
            onCaptureDesktop: { [weak self] in self?.onCaptureDesktop?() },
            onCaptureArea: { [weak self] in self?.onCaptureArea?() },
            onCaptureWindow: { [weak self] in self?.onCaptureWindow?() },
            onOpenSettings: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        )
        let clipboardHistoryProvider = ClipboardHistoryProvider()
        let appLauncherProvider = AppLauncherProvider()

        self.controller = CommandPaletteController(providers: [
            atlasProvider,
            clipboardHistoryProvider,
            appLauncherProvider,
        ])

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
        onCaptureWindow: @escaping () -> Void
    ) {
        self.onCaptureDesktop = onCaptureDesktop
        self.onCaptureArea = onCaptureArea
        self.onCaptureWindow = onCaptureWindow
    }

    private func registerHotkey(_ config: HotkeyConfig) {
        let flags = NSEvent.ModifierFlags(rawValue: config.modifiers)
        hotkeyService.register(keyCode: config.keyCode, modifiers: flags) { [weak self] in
            self?.controller?.toggle()
        }
    }
}
