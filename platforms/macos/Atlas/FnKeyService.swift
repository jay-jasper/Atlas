import Foundation

enum FnKeyMode: Int, CaseIterable, Identifiable {
    case fnKeys = 0       // F1-F12 send hardware function keys
    case mediaKeys = 1    // F1-F12 send media/brightness actions

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fnKeys: return "Standard Fn Keys"
        case .mediaKeys: return "Media / Special Keys"
        }
    }

    var description: String {
        switch self {
        case .fnKeys: return "F1–F12 act as function keys. Hold Fn for media actions."
        case .mediaKeys: return "F1–F12 act as media/brightness keys. Hold Fn for function keys."
        }
    }

    var systemImage: String {
        switch self {
        case .fnKeys: return "fn"
        case .mediaKeys: return "music.note"
        }
    }
}

protocol FnKeyControlling {
    func readMode() -> FnKeyMode?
    func setMode(_ mode: FnKeyMode) -> Bool
}

@MainActor
final class FnKeyService: ObservableObject {
    @Published private(set) var currentMode: FnKeyMode = .mediaKeys
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var isAvailable: Bool = false

    private let controller: FnKeyControlling

    init(controller: FnKeyControlling = LiveFnKeyController()) {
        self.controller = controller
        refresh()
    }

    func refresh() {
        if let mode = controller.readMode() {
            currentMode = mode
            isAvailable = true
            statusMessage = ""
        } else {
            isAvailable = false
            statusMessage = "Unable to read Fn key mode. Try running with elevated privileges."
        }
    }

    func setMode(_ mode: FnKeyMode) {
        guard controller.setMode(mode) else {
            statusMessage = "Failed to set Fn key mode."
            return
        }
        currentMode = mode
        statusMessage = ""
    }
}

/// Reads and writes the macOS "Use F1, F2, etc. as standard function keys"
/// preference, which is backed by the `com.apple.keyboard.fnState` key in the
/// global preferences domain (`-g`). `fnState == true` means the F-keys act as
/// standard function keys (`.fnKeys`); otherwise they default to media keys.
///
/// Changes persist immediately but the HID system applies them on next login.
struct LiveFnKeyController: FnKeyControlling {
    private static let domain = "com.apple.keyboard.fnState"
    private let commandRunner: SystemCommandRunning

    init(commandRunner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func readMode() -> FnKeyMode? {
        guard let result = try? commandRunner.run(
            "/usr/bin/defaults",
            arguments: ["read", "-g", Self.domain]
        ) else {
            // The key is unset until the user changes it; default is media keys.
            return .mediaKeys
        }
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return output == "1" ? .fnKeys : .mediaKeys
    }

    func setMode(_ mode: FnKeyMode) -> Bool {
        let enabled = (mode == .fnKeys) ? "true" : "false"
        guard let result = try? commandRunner.run(
            "/usr/bin/defaults",
            arguments: ["write", "-g", Self.domain, "-bool", enabled]
        ) else { return false }
        return result.succeeded
    }
}

// Fallback using nvram for systems where IOKit HID access is restricted
struct NvramFnKeyController: FnKeyControlling {
    private let commandRunner: SystemCommandRunning

    init(commandRunner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func readMode() -> FnKeyMode? {
        guard let result = try? commandRunner.run("/usr/sbin/nvram", arguments: ["KeyboardSupport:fnMode"]),
              result.succeeded else { return nil }
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.hasSuffix("0") { return .fnKeys }
        if output.hasSuffix("1") { return .mediaKeys }
        return nil
    }

    func setMode(_ mode: FnKeyMode) -> Bool {
        guard let result = try? commandRunner.run(
            "/usr/sbin/nvram",
            arguments: ["KeyboardSupport:fnMode=\(mode.rawValue)"]
        ) else { return false }
        return result.succeeded
    }
}
