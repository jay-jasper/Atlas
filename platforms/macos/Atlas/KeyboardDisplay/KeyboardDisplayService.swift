import AppKit
import CoreGraphics

@MainActor
final class KeyboardDisplayService: ObservableObject {
    struct Keystroke: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var recent: [Keystroke] = []
    @Published private(set) var isCapturing = false
    @Published private(set) var statusMessage = ""

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private static let maxRecent = 12

    /// Records a formatted keystroke (called by the tap or by tests).
    func record(modifiers: KeyModifiers, characters: String, keyCode: Int) {
        let text = KeyEventFormatter.display(modifiers: modifiers, characters: characters, keyCode: keyCode)
        recent.append(Keystroke(text: text))
        if recent.count > Self.maxRecent {
            recent.removeFirst(recent.count - Self.maxRecent)
        }
    }

    func clear() {
        recent.removeAll()
    }

    func startCapture() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<KeyboardDisplayService>.fromOpaque(refcon).takeUnretainedValue()
            service.handle(event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            statusMessage = "Accessibility permission required."
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isCapturing = true
        statusMessage = ""
    }

    func stopCapture() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isCapturing = false
    }

    private nonisolated func handle(_ event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        var modifiers: KeyModifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        let characters = length > 0 ? String(utf16CodeUnits: chars, count: length) : ""

        Task { @MainActor [weak self] in
            self?.record(modifiers: modifiers, characters: characters, keyCode: keyCode)
        }
    }
}
