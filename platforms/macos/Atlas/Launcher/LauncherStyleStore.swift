import Foundation

@MainActor
final class LauncherStyleStore: ObservableObject {
    private static let storageKey = "launcher.style"

    @Published var style: LauncherStyle {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(LauncherStyle.self, from: data) {
            style = decoded.sanitized()
        } else {
            style = .default
        }
    }

    func reset() {
        style = .default
    }

    private func save() {
        guard let data = try? encoder.encode(style) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
