import AppKit
import Carbon

/// System-wide hotkeys via Carbon RegisterEventHotKey: fires regardless of
/// which app or text field has focus, needs no Accessibility permission, and
/// consumes the keystroke (⌥Space won't type a space into the focused input).
@MainActor
final class GlobalHotkeyService {
    private struct Registration {
        let id: UInt32
        let keyCode: Int
        let modifiers: NSEvent.ModifierFlags
        let handler: () -> Void
        var hotKeyRef: EventHotKeyRef?
    }

    // US QWERTY key code for '4'. Together with Ctrl+Shift, this represents Ctrl+Shift+4.
    private let legacyAreaCaptureKeyCode = 21

    // Legacy single-callback compatibility
    var onAreaCapture: (() -> Void)? {
        didSet {
            unregister(keyCode: legacyAreaCaptureKeyCode, modifiers: [.control, .shift])
            if let cb = onAreaCapture {
                register(keyCode: legacyAreaCaptureKeyCode, modifiers: [.control, .shift], handler: cb)
            }
        }
    }

    private var registrations: [Registration] = []
    private var eventHandlerRef: EventHandlerRef?
    private var isStarted = false
    private var nextID: UInt32 = 1
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
        unregister(keyCode: keyCode, modifiers: normalizedModifiers)

        var registration = Registration(
            id: nextID,
            keyCode: keyCode,
            modifiers: normalizedModifiers,
            handler: handler,
            hotKeyRef: nil
        )
        nextID += 1
        if isStarted {
            registration.hotKeyRef = registerWithCarbon(registration)
        }
        registrations.append(registration)
    }

    func unregister(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        let normalizedModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        for registration in registrations
        where registration.keyCode == keyCode && registration.modifiers == normalizedModifiers {
            if let ref = registration.hotKeyRef {
                UnregisterEventHotKey(ref)
            }
        }
        registrations.removeAll { $0.keyCode == keyCode && $0.modifiers == normalizedModifiers }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard hotKeyID.signature == GlobalHotkeyService.signature else { return noErr }
                let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    service.fire(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        for index in registrations.indices where registrations[index].hotKeyRef == nil {
            registrations[index].hotKeyRef = registerWithCarbon(registrations[index])
        }
    }

    func stop() {
        for registration in registrations {
            if let ref = registration.hotKeyRef {
                UnregisterEventHotKey(ref)
            }
        }
        for index in registrations.indices {
            registrations[index].hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
        isStarted = false
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
        for registration in registrations
        where registration.keyCode == keyCode && registration.modifiers == flags {
            registration.handler()
            return
        }
    }

    // MARK: - Carbon plumbing

    private func fire(id: UInt32) {
        registrations.first { $0.id == id }?.handler()
    }

    private func registerWithCarbon(_ registration: Registration) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: registration.id)
        let status = RegisterEventHotKey(
            UInt32(registration.keyCode),
            Self.carbonModifiers(from: registration.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        return status == noErr ? ref : nil
    }

    static let signature: OSType = {
        // "ATLS"
        OSType(0x41544C53)
    }()

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    deinit {
        let refs = registrations.compactMap(\.hotKeyRef)
        let handler = eventHandlerRef
        if !refs.isEmpty || handler != nil {
            DispatchQueue.main.async {
                refs.forEach { UnregisterEventHotKey($0) }
                if let handler { RemoveEventHandler(handler) }
            }
        }
    }
}
