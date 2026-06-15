import Foundation
import IOKit
import IOKit.hid

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

struct LiveFnKeyController: FnKeyControlling {
    private static let hidKeyboardUsagePage: UInt32 = 0xFF00
    private static let hidFKeyMode: UInt32 = 0x0003

    func readMode() -> FnKeyMode? {
        guard let service = openKeyboardService() else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            kIOHIDFKeyModeKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else { return nil }
        return FnKeyMode(rawValue: property.intValue)
    }

    func setMode(_ mode: FnKeyMode) -> Bool {
        guard let service = openKeyboardService() else { return false }
        defer { IOObjectRelease(service) }

        let kr = IORegistryEntrySetCFProperty(
            service,
            kIOHIDFKeyModeKey as CFString,
            NSNumber(value: mode.rawValue)
        )
        return kr == kIOReturnSuccess
    }

    private func openKeyboardService() -> io_service_t? {
        let matching = IOServiceMatching("AppleHIDKeyboardEventDriverV2") as CFMutableDictionary?
            ?? IOServiceMatching("IOHIDKeyboard") as CFMutableDictionary?
        guard let matching else { return nil }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        return service == IO_OBJECT_NULL ? nil : service
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
