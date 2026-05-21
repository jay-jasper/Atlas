import AppKit
import SwiftUI
import Carbon

struct HotkeyConfig {
    let keyCode: Int
    let modifiers: UInt

    static func load(from defaults: UserDefaults = .standard) -> HotkeyConfig {
        let keyCode = defaults.object(forKey: "palette.hotkey.keyCode") as? Int ?? 49
        let modifiers = defaults.object(forKey: "palette.hotkey.modifiers") as? UInt
            ?? NSEvent.ModifierFlags.option.rawValue
        return HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(keyCode, forKey: "palette.hotkey.keyCode")
        defaults.set(modifiers, forKey: "palette.hotkey.modifiers")
    }

    static func isValid(modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.intersection([.command, .option, .control, .shift]).isEmpty
    }

    var conflictsWithAreaCapture: Bool {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
            .intersection(.deviceIndependentFlagsMask)
        let areaFlags = NSEvent.ModifierFlags([.control, .shift])
            .intersection(.deviceIndependentFlagsMask)
        return keyCode == 21 && flags == areaFlags
    }

    func displayString(keyChar: String) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts = ""
        if flags.contains(.control)  { parts += "⌃" }
        if flags.contains(.option)   { parts += "⌥" }
        if flags.contains(.shift)    { parts += "⇧" }
        if flags.contains(.command)  { parts += "⌘" }
        return parts + keyChar
    }
}

struct KeyRecorderView: View {
    @State private var config: HotkeyConfig = .load()
    @State private var isRecording: Bool = false
    @State private var showConflictWarning: Bool = false
    private let onConfigChanged: (HotkeyConfig) -> Void

    init(onConfigChanged: @escaping (HotkeyConfig) -> Void) {
        self.onConfigChanged = onConfigChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Global Shortcut")
                Spacer()
                shortcutBadge
            }
            if showConflictWarning {
                Text("⚠️ This shortcut conflicts with Area Capture (⌃⇧4).")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .onAppear {
            config = .load()
            showConflictWarning = config.conflictsWithAreaCapture
        }
    }

    @ViewBuilder
    private var shortcutBadge: some View {
        let label = isRecording ? "Press shortcut…" : displayLabel
        Text(label)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isRecording
                ? Color.accentColor.opacity(0.15)
                : Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(5)
            .onTapGesture { isRecording = true }
            .background(HotkeyCaptureView(isActive: isRecording) { keyCode, modifiers in
                guard HotkeyConfig.isValid(modifiers: modifiers) else { return }
                let newConfig = HotkeyConfig(keyCode: keyCode, modifiers: modifiers.rawValue)
                config = newConfig
                newConfig.save()
                showConflictWarning = newConfig.conflictsWithAreaCapture
                isRecording = false
                onConfigChanged(newConfig)
            })
    }

    private var displayLabel: String {
        let keyChar = keyCharForCode(config.keyCode)
        return config.displayString(keyChar: keyChar)
    }

    private func keyCharForCode(_ code: Int) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 53: return "⎋"
        default:
            if let str = keyStringFromKeyCode(UInt16(code)) { return str.uppercased() }
            return "(\(code))"
        }
    }

    private func keyStringFromKeyCode(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        UCKeyTranslate(keyboardLayout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                       OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &len, &chars)
        return len > 0 ? String(utf16CodeUnits: chars, count: len) : nil
    }
}

private struct HotkeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HotkeyCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? HotkeyCaptureNSView)?.isCapturing = isActive
        if isActive { nsView.window?.makeFirstResponder(nsView) }
    }
}

private final class HotkeyCaptureNSView: NSView {
    var isCapturing = false
    var onCapture: ((Int, NSEvent.ModifierFlags) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        onCapture?(Int(event.keyCode), flags)
    }
}
