import ApplicationServices
import Foundation

protocol WindowManagementPermissionChecking {
    var isTrusted: Bool { get }
    func requestPermission()
}

struct AccessibilityPermissionChecker: WindowManagementPermissionChecking {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
