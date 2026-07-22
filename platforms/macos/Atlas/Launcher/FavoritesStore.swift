import Foundation

@MainActor
final class FavoritesStore: ObservableObject {
    private static let storageKey = "launcher.favorites"

    @Published private(set) var pinnedKeys: [String] {
        didSet { defaults.set(pinnedKeys, forKey: Self.storageKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinnedKeys = defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    func isPinned(_ key: String) -> Bool {
        pinnedKeys.contains(key)
    }

    func toggle(_ key: String) {
        if let index = pinnedKeys.firstIndex(of: key) {
            pinnedKeys.remove(at: index)
        } else {
            pinnedKeys.append(key)
        }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        pinnedKeys.move(fromOffsets: source, toOffset: destination)
    }
}
