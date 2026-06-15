import AppKit
import CoreGraphics

protocol TextExpansionMonitoring: AnyObject {
    /// Called with the rolling typed buffer; returns an expansion match or nil.
    var onResolveExpansion: ((String) -> TextExpansionEngine.Match?)? { get set }
    func start() -> Bool
    func stop()
}

/// Live system-wide text expansion via a `CGEventTap`. Requires Accessibility
/// permission. Maintains a rolling buffer of typed characters; when the tail
/// matches a snippet trigger, it deletes the trigger and inserts the expansion
/// via the pasteboard.
final class TextExpansionMonitor: TextExpansionMonitoring {
    var onResolveExpansion: ((String) -> TextExpansionEngine.Match?)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = ""
    private var suppressCapture = false
    private static let maxBuffer = 64

    func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TextExpansionMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        buffer = ""
    }

    private func handle(event: CGEvent) {
        guard !suppressCapture else { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // Reset on space / return / delete to keep the buffer to a single token.
        if keyCode == 49 || keyCode == 36 || keyCode == 51 {
            buffer = ""
            return
        }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0, let scalar = String(utf16CodeUnits: chars, count: length) as String? else { return }
        buffer.append(scalar)
        if buffer.count > Self.maxBuffer {
            buffer.removeFirst(buffer.count - Self.maxBuffer)
        }
        if let match = onResolveExpansion?(buffer) {
            apply(match)
            buffer = ""
        }
    }

    private func apply(_ match: TextExpansionEngine.Match) {
        suppressCapture = true
        defer { suppressCapture = false }

        // Delete the trigger characters.
        for _ in 0..<match.deleteCount {
            postKey(virtualKey: 51) // delete/backspace
        }
        // Insert via pasteboard + Cmd+V, preserving the prior clipboard.
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(match.insertText, forType: .string)
        postKey(virtualKey: 9, command: true) // 'v'
        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    private func postKey(virtualKey: CGKeyCode, command: Bool = false) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        if command {
            down?.flags = .maskCommand
            up?.flags = .maskCommand
        }
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
