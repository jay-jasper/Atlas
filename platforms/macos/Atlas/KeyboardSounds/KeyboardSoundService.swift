import AppKit
import CoreGraphics

@MainActor
final class KeyboardSoundService: ObservableObject {
    @Published var pack: KeyboardSoundPack = .mechanical
    @Published var volume: Double = 0.5
    @Published var isEnabled = false {
        didSet { isEnabled ? start() : stop() }
    }
    @Published private(set) var statusMessage = ""

    private let player: SoundPlaying
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(player: SoundPlaying = NSSoundPlayer()) {
        self.player = player
    }

    /// Plays the keystroke sound for a keycode. Exposed for testing.
    func playKey(keyCode: Int) {
        let name = KeyboardSoundSelector.sound(for: keyCode, pack: pack)
        player.play(named: name)
    }

    private func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<KeyboardSoundService>.fromOpaque(refcon).takeUnretainedValue()
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            Task { @MainActor in service.playKey(keyCode: keyCode) }
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
        statusMessage = ""
    }

    private func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }
}
