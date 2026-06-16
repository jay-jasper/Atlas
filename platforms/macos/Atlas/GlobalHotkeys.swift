import AppKit
import Carbon.HIToolbox

/// Thin wrapper over Carbon `RegisterEventHotKey` for app-wide global shortcuts
/// (work even when Atlas isn't focused). Used by the screenshot feature for
/// Snipaste-style 截图 / 贴图 / 隐藏贴图 hotkeys.
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, _ handler: @escaping () -> Void) -> UInt32 {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x41544C53), id: id) // 'ATLS'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
            handlers[id] = handler
        }
        return id
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handlers[hkID.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}

/// Default Snipaste-style global shortcuts, registered once at launch when
/// enabled in settings. Modifiers are control+option to avoid system clashes.
enum ScreenshotHotkeys {
    private static let ctrlOpt = UInt32(controlKey | optionKey)
    private static var didRegister = false

    /// Human-readable labels shown in the settings panel.
    static let descriptions: [(action: String, shortcut: String)] = [
        ("区域 / 窗口截图", "⌃⌥A"),
        ("全屏截图", "⌃⌥F"),
        ("贴图(从剪贴板)", "⌃⌥V"),
        ("隐藏 / 显示所有贴图", "⌃⌥H"),
    ]

    static func applyFromSettings() {
        GlobalHotkeyManager.shared.unregisterAll()
        guard ScreenshotSettings.shared.hotkeysEnabled else { return }
        let m = GlobalHotkeyManager.shared
        m.register(keyCode: UInt32(kVK_ANSI_A), modifiers: ctrlOpt) {
            ScreenshotActions.captureRegion()
        }
        m.register(keyCode: UInt32(kVK_ANSI_F), modifiers: ctrlOpt) {
            ScreenshotActions.captureFull()
        }
        m.register(keyCode: UInt32(kVK_ANSI_V), modifiers: ctrlOpt) {
            ScreenshotActions.pinFromClipboard()
        }
        m.register(keyCode: UInt32(kVK_ANSI_H), modifiers: ctrlOpt) {
            PinnedScreenshotWindow.toggleHideAll()
        }
    }
}
