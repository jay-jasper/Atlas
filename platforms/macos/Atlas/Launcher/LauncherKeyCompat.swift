import AppKit
import SwiftUI

enum KeyPressResultCompatible {
    case handled
    case ignored
}

enum CompatibleKey {
    case escape
    case upArrow
    case downArrow
    case `return`
    case tab

    @available(macOS 14.0, *)
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .escape: .escape
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .return: .return
        case .tab: .tab
        }
    }
}

struct KeyPressModifier: ViewModifier {
    let key: CompatibleKey
    let action: () -> KeyPressResultCompatible

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress(key.keyEquivalent) {
                action() == .handled ? .handled : .ignored
            }
        } else {
            content
                .onAppear {
                    if monitor == nil {
                        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                            if matches(event) {
                                if action() == .handled {
                                    return nil // consumed
                                }
                            }
                            return event
                        }
                    }
                }
                .onDisappear {
                    if let monitor {
                        NSEvent.removeMonitor(monitor)
                        self.monitor = nil
                    }
                }
        }
    }

    private func matches(_ event: NSEvent) -> Bool {
        switch key {
        case .escape:
            return event.keyCode == 53
        case .upArrow:
            return event.keyCode == 126
        case .downArrow:
            return event.keyCode == 125
        case .return:
            return event.keyCode == 36 || event.keyCode == 76
        case .tab:
            return event.keyCode == 48
        }
    }
}

extension View {
    func onKeyPressCompatible(_ key: CompatibleKey, action: @escaping () -> KeyPressResultCompatible) -> some View {
        self.modifier(KeyPressModifier(key: key, action: action))
    }
}
