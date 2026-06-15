import Foundation

/// A system toggle exposed by the Quick Switches module. Each switch maps to a
/// shell command (typically AppleScript via `osascript` or a CLI) for reading
/// and setting state. Command construction is pure and unit-testable; execution
/// is delegated to an injected runner.
enum QuickSwitchID: String, CaseIterable, Codable {
    case darkMode
    case doNotDisturb
    case bluetooth
    case keepAwake

    var title: String {
        switch self {
        case .darkMode: return "Dark Mode"
        case .doNotDisturb: return "Do Not Disturb"
        case .bluetooth: return "Bluetooth"
        case .keepAwake: return "Keep Awake"
        }
    }

    var systemImage: String {
        switch self {
        case .darkMode: return "moon.fill"
        case .doNotDisturb: return "bell.slash.fill"
        case .bluetooth: return "wave.3.right"
        case .keepAwake: return "cup.and.saucer.fill"
        }
    }
}

/// Builds the `osascript`/CLI command for setting a quick switch on or off.
enum QuickSwitchCommandBuilder {
    static func setCommand(_ id: QuickSwitchID, on: Bool) -> (executable: String, arguments: [String]) {
        switch id {
        case .darkMode:
            let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)"
            return ("/usr/bin/osascript", ["-e", script])
        case .doNotDisturb:
            // Toggle via the Focus shortcut; falls back gracefully if absent.
            return ("/usr/bin/shortcuts", ["run", on ? "Turn On Do Not Disturb" : "Turn Off Do Not Disturb"])
        case .bluetooth:
            return ("/usr/local/bin/blueutil", ["--power", on ? "1" : "0"])
        case .keepAwake:
            // Handled in-process by KeepAwakeService; command is a no-op marker.
            return ("/usr/bin/true", [])
        }
    }
}
