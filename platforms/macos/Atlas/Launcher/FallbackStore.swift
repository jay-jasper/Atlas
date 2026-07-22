import AppKit
import Foundation

struct FallbackCommand: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var template: String
    var enabled: Bool

    static let defaults: [FallbackCommand] = [
        FallbackCommand(
            id: "google",
            name: "Search Google",
            template: "https://www.google.com/search?q={query}",
            enabled: true
        ),
        FallbackCommand(
            id: "duckduckgo",
            name: "Search DuckDuckGo",
            template: "https://duckduckgo.com/?q={query}",
            enabled: true
        ),
        FallbackCommand(
            id: "translate",
            name: "Translate",
            template: "https://translate.google.com/?text={query}",
            enabled: false
        ),
    ]
}

@MainActor
final class FallbackStore: ObservableObject {
    private static let storageKey = "launcher.fallbacks"

    @Published private(set) var commands: [FallbackCommand] {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([FallbackCommand].self, from: data),
           !decoded.isEmpty {
            commands = decoded
        } else {
            commands = FallbackCommand.defaults
        }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        commands.move(fromOffsets: source, toOffset: destination)
    }

    func setEnabled(_ enabled: Bool, id: String) {
        guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[index].enabled = enabled
    }

    /// The whole query is the argument for fallback commands.
    func makeItems(query: String) -> [LauncherItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return commands.filter(\.enabled).map { command in
            LauncherItem(
                id: "Fallback|\(command.name)",
                title: command.name,
                subtitle: "\"\(trimmed)\"",
                icon: .sfSymbol("magnifyingglass"),
                category: "Fallback",
                actions: [
                    LauncherAction(id: "search", title: "Search", systemImage: "magnifyingglass", shortcutHint: "↵") {
                        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
                        if let url = URL(string: command.template.replacingOccurrences(of: "{query}", with: encoded)) {
                            NSWorkspace.shared.open(url)
                        }
                        return .dismiss
                    },
                ],
                acceptsArgument: true
            )
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
