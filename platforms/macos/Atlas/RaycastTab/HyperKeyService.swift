import AppKit
import Carbon.HIToolbox
import Foundation

/// Hyper Key:指定触发键按住 = ⌘⌥⌃⇧ 组合;单击 = 可配行为(Esc/原键/无)。
/// EventTapService 订阅者。CapsLock 走 flagsChanged(keyCode 57)。
@MainActor
final class HyperKeyService: ObservableObject {
    static let shared = HyperKeyService()

    enum TriggerKey: String, CaseIterable, Identifiable {
        case capsLock
        case f13, f14, f15, f16, f17, f18, f19
        case rightCommand
        case rightOption

        var id: String { rawValue }

        var keyCode: CGKeyCode {
            switch self {
            case .capsLock: return 57
            case .f13: return 105
            case .f14: return 107
            case .f15: return 113
            case .f16: return 106
            case .f17: return 64
            case .f18: return 79
            case .f19: return 80
            case .rightCommand: return 54
            case .rightOption: return 61
            }
        }

        var display: String {
            switch self {
            case .capsLock: return "⇪ Caps Lock"
            case .rightCommand: return loc("右 ⌘", "Right ⌘")
            case .rightOption: return loc("右 ⌥", "Right ⌥")
            default: return rawValue.uppercased()
            }
        }
    }

    enum TapBehavior: String, CaseIterable, Identifiable {
        case escape
        case original
        case none

        var id: String { rawValue }

        var display: String {
            switch self {
            case .escape: return "Esc"
            case .original: return loc("原键", "Original key")
            case .none: return loc("无", "None")
            }
        }
    }

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "hyperkey.enabled")
            applyState()
        }
    }
    @Published var trigger: TriggerKey {
        didSet { UserDefaults.standard.set(trigger.rawValue, forKey: "hyperkey.trigger") }
    }
    @Published var tapBehavior: TapBehavior {
        didSet { UserDefaults.standard.set(tapBehavior.rawValue, forKey: "hyperkey.tap") }
    }

    private var isHolding = false
    private var didCombine = false
    private var holdStartedAt: TimeInterval = 0

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "hyperkey.enabled")
        trigger = TriggerKey(rawValue: UserDefaults.standard.string(forKey: "hyperkey.trigger") ?? "") ?? .capsLock
        tapBehavior = TapBehavior(rawValue: UserDefaults.standard.string(forKey: "hyperkey.tap") ?? "") ?? .escape
        applyState()
    }

    private func applyState() {
        if isEnabled, EventTapService.shared.isAccessibilityTrusted {
            EventTapService.shared.subscribe(id: "hyper-key") { [weak self] event, type in
                self?.handle(event: event, type: type) ?? event
            }
        } else {
            EventTapService.shared.unsubscribe(id: "hyper-key")
        }
    }

    private nonisolated func handle(event: CGEvent, type: CGEventType) -> CGEvent? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let triggerCode = MainActor.assumeIsolated { trigger.keyCode }

        // CapsLock/右修饰键走 flagsChanged。
        if type == .flagsChanged, keyCode == triggerCode {
            let anyRelevantFlag: Bool
            switch triggerCode {
            case 57: anyRelevantFlag = event.flags.contains(.maskAlphaShift)
            case 54: anyRelevantFlag = event.flags.contains(.maskCommand)
            case 61: anyRelevantFlag = event.flags.contains(.maskAlternate)
            default: anyRelevantFlag = true
            }
            MainActor.assumeIsolated {
                if anyRelevantFlag {
                    isHolding = true
                    didCombine = false
                    holdStartedAt = Date().timeIntervalSince1970
                } else {
                    let wasCombo = didCombine
                    let heldMs = (Date().timeIntervalSince1970 - holdStartedAt) * 1000
                    isHolding = false
                    if !wasCombo, heldMs < 300 {
                        performTapBehavior()
                    }
                }
            }
            return nil // 吞掉触发键本身(CapsLock 不再切换大写)
        }

        if type == .keyDown, keyCode == triggerCode {
            // F 键类触发:keyDown 按住
            MainActor.assumeIsolated {
                isHolding = true
                didCombine = false
                holdStartedAt = Date().timeIntervalSince1970
            }
            return nil
        }

        if type == .keyDown {
            let holding = MainActor.assumeIsolated { isHolding }
            if holding {
                MainActor.assumeIsolated { didCombine = true }
                event.flags.insert([.maskCommand, .maskAlternate, .maskControl, .maskShift])
                return event
            }
        }
        return event
    }

    private func performTapBehavior() {
        switch tapBehavior {
        case .none:
            return
        case .escape:
            postKey(CGKeyCode(kVK_Escape))
        case .original:
            postKey(trigger.keyCode)
        }
    }

    private func postKey(_ keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)?
                .post(tap: .cgSessionEventTap)
        }
    }
}
