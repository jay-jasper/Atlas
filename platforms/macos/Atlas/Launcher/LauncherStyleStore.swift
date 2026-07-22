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
            var migrated = decoded.sanitized()
            // 旧默认背景(material 0.85)迁移为「跟随主题」。
            if migrated.background == .material(opacity: 0.85) {
                migrated.background = .theme
            }
            style = migrated
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
