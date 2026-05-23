import AppKit

@MainActor
final class GlobalHotkeyService {
    private struct Registration {
        let keyCode: Int
        let modifiers: NSEvent.ModifierFlags
        let handler: () -> Void
    }

    // US QWERTY key code for '4'. Together with Ctrl+Shift, this represents Ctrl+Shift+4.
    private let legacyAreaCaptureKeyCode = 21

    // Legacy single-callback compatibility
    var onAreaCapture: (() -> Void)? {
        didSet {
            // Unregister any existing legacy registration to prevent duplicates and leaks
            unregister(keyCode: legacyAreaCaptureKeyCode, modifiers: [.control, .shift])
            if let cb = onAreaCapture {
                register(keyCode: legacyAreaCaptureKeyCode, modifiers: [.control, .shift], handler: cb)
            }
        }
    }

    private var registrations: [Registration] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let accessLogger: PrivacyPulseAccessLogging
    private let isProcessTrusted: () -> Bool
    private let requestTrustWithPrompt: () -> Void

    var registeredCount: Int { registrations.count }

    init(
        accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger(),
        isProcessTrusted: @escaping () -> Bool = AXIsProcessTrusted,
        requestTrustWithPrompt: @escaping () -> Void = {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
            AXIsProcessTrustedWithOptions(options)
        }
    ) {
        self.accessLogger = accessLogger
        self.isProcessTrusted = isProcessTrusted
        self.requestTrustWithPrompt = requestTrustWithPrompt
    }

    func register(keyCode: Int, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        let normalizedModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        // Clean up any existing registration for the same shortcut to prevent duplicates
        unregister(keyCode: keyCode, modifiers: normalizedModifiers)
        registrations.append(Registration(keyCode: keyCode, modifiers: normalizedModifiers, handler: handler))
    }

    func unregister(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        let normalizedModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        registrations.removeAll { $0.keyCode == keyCode && $0.modifiers == normalizedModifiers }
    }

    func start() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }

        guard isProcessTrusted() else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor  = nil
    }

    func requestAccessibilityIfNeeded() {
        accessLogger.record(
            category: .accessibility,
            title: "Accessibility Check",
            detail: "Global hotkey trust checked"
        )
        guard !isProcessTrusted() else { return }
        requestTrustWithPrompt()
    }

    // Internal for testing: fire the matching handler synchronously
    func simulateKeyEvent(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        for reg in registrations {
            let regFlags = reg.modifiers.intersection(.deviceIndependentFlagsMask)
            if reg.keyCode == keyCode, regFlags == flags {
                reg.handler()
                return
            }
        }
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        for reg in registrations {
            let regFlags = reg.modifiers.intersection(.deviceIndependentFlagsMask)
            if reg.keyCode == Int(event.keyCode), regFlags == flags {
                // Executed synchronously on MainActor for predictability and test alignment
                reg.handler()
                return nil
            }
        }
        return event
    }

    deinit {
        // Capture event monitors and remove them asynchronously on the main thread 
        // to guarantee safety across actor-isolation boundaries during deallocation
        let gMonitor = globalMonitor
        let lMonitor = localMonitor
        if gMonitor != nil || lMonitor != nil {
            DispatchQueue.main.async {
                if let m = gMonitor { NSEvent.removeMonitor(m) }
                if let m = lMonitor { NSEvent.removeMonitor(m) }
            }
        }
    }
}
