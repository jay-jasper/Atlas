import Foundation

/// Enabled widgets and their order on the 组件面板.
@MainActor
final class WidgetStore: ObservableObject {
    private static let storageKey = "menuPanel.widgets"
    static let defaultWidgets: [WidgetKind] = [.gauges, .network]

    @Published private(set) var enabled: [WidgetKind] {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([WidgetKind].self, from: data),
           !decoded.isEmpty {
            enabled = decoded
        } else {
            enabled = Self.defaultWidgets
        }
    }

    func isEnabled(_ kind: WidgetKind) -> Bool {
        enabled.contains(kind)
    }

    func add(_ kind: WidgetKind) {
        guard !enabled.contains(kind) else { return }
        enabled.append(kind)
    }

    func remove(_ kind: WidgetKind) {
        enabled.removeAll { $0 == kind }
    }

    func moveUp(_ kind: WidgetKind) {
        guard let index = enabled.firstIndex(of: kind), index > 0 else { return }
        enabled.swapAt(index, index - 1)
    }

    func moveDown(_ kind: WidgetKind) {
        guard let index = enabled.firstIndex(of: kind), index < enabled.count - 1 else { return }
        enabled.swapAt(index, index + 1)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(enabled) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
