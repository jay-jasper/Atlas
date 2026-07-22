import Foundation

@MainActor
final class CommandHotkeyStore: ObservableObject {
    private static let storageKey = "launcher.commandHotkeys"

    private struct Entry: Codable {
        let keyCode: Int
        let modifiers: UInt
    }

    /// commandKey → hotkey
    @Published private(set) var hotkeys: [String: HotkeyConfig] {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let entries = try? JSONDecoder().decode([String: Entry].self, from: data) {
            hotkeys = entries.mapValues { HotkeyConfig(keyCode: $0.keyCode, modifiers: $0.modifiers) }
        } else {
            hotkeys = [:]
        }
    }

    func set(_ config: HotkeyConfig?, for key: String) {
        if let config {
            hotkeys[key] = config
        } else {
            hotkeys.removeValue(forKey: key)
        }
    }

    private func save() {
        let entries = hotkeys.mapValues { Entry(keyCode: $0.keyCode, modifiers: $0.modifiers) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
