import AppKit
import Carbon.HIToolbox
import SwiftUI

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

/// A key + Carbon-modifier combination, packed into one Int for persistence.
struct HotkeyBinding: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon modifier flags (cmdKey/optionKey/...)

    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(packed: Int) { keyCode = UInt32(packed & 0xFFFF); modifiers = UInt32((packed >> 16) & 0xFFFF) }

    var packed: Int { Int(keyCode) | (Int(modifiers) << 16) }
    var isValid: Bool { modifiers != 0 }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    /// Carbon modifier mask from an `NSEvent.ModifierFlags`.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
    static func keyName(_ code: UInt32) -> String { names[code] ?? "·" }
}

/// Snipaste-style global shortcuts, registered when enabled in settings. Each
/// action's combination is user-customizable (see `HotkeyRecorderView`).
enum ScreenshotHotkeys {
    static func applyFromSettings() {
        GlobalHotkeyManager.shared.unregisterAll()
        let s = ScreenshotSettings.shared
        guard s.hotkeysEnabled else { return }
        let m = GlobalHotkeyManager.shared
        bind(m, s.hotkeyRegion) { ScreenshotActions.captureRegion() }
        bind(m, s.hotkeyFull) { ScreenshotActions.captureFull() }
        bind(m, s.hotkeyPin) { ScreenshotActions.pinFromClipboard() }
        bind(m, s.hotkeyHide) { PinnedScreenshotWindow.toggleHideAll() }
    }

    private static func bind(_ m: GlobalHotkeyManager, _ b: HotkeyBinding, _ handler: @escaping () -> Void) {
        guard b.isValid else { return }
        m.register(keyCode: b.keyCode, modifiers: b.modifiers, handler)
    }

    static var defaults: (region: Int, full: Int, pin: Int, hide: Int) {
        let ctrlOpt = UInt32(controlKey | optionKey)
        return (
            HotkeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: ctrlOpt).packed,
            HotkeyBinding(keyCode: UInt32(kVK_ANSI_F), modifiers: ctrlOpt).packed,
            HotkeyBinding(keyCode: UInt32(kVK_ANSI_V), modifiers: ctrlOpt).packed,
            HotkeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: ctrlOpt).packed
        )
    }
}

/// A SwiftUI control that records a key combination: click to arm, then press
/// the desired shortcut. Esc cancels recording.
struct HotkeyRecorderView: View {
    @Binding var binding: HotkeyBinding
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            Text(recording ? "按下快捷键…" : binding.display)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 96)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc cancels
            let mods = HotkeyBinding.carbonModifiers(event.modifierFlags)
            guard mods != 0 else { return nil }           // require at least one modifier
            binding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: mods)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
