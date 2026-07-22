import Foundation

@MainActor
final class AliasStore: ObservableObject, AliasResolving {
    private static let storageKey = "launcher.aliases"

    /// commandKey → alias (lowercased)
    @Published private(set) var aliases: [String: String] {
        didSet { defaults.set(aliases, forKey: Self.storageKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aliases = (defaults.dictionary(forKey: Self.storageKey) as? [String: String]) ?? [:]
    }

    func alias(for key: String) -> String? {
        aliases[key]
    }

    func setAlias(_ alias: String?, for key: String) {
        let normalized = alias?.trimmingCharacters(in: .whitespaces).lowercased()
        guard let normalized, !normalized.isEmpty else {
            aliases.removeValue(forKey: key)
            return
        }
        // An alias points at exactly one command — last write wins.
        for (existingKey, existingAlias) in aliases where existingAlias == normalized && existingKey != key {
            aliases.removeValue(forKey: existingKey)
        }
        aliases[key] = normalized
    }

    /// Exact match, or the query is a prefix of an alias.
    nonisolated func commandKey(matching query: String) -> String? {
        let lowered = query.lowercased()
        guard !lowered.isEmpty else { return nil }
        let snapshot = MainActor.assumeIsolated { aliases }
        if let exact = snapshot.first(where: { $0.value == lowered }) {
            return exact.key
        }
        return snapshot
            .filter { $0.value.hasPrefix(lowered) }
            .sorted { $0.value < $1.value }
            .first?.key
    }
}
