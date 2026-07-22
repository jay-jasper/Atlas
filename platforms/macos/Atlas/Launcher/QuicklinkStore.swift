import AppKit
import Foundation

struct Quicklink: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var template: String

    init(id: UUID = UUID(), name: String, template: String) {
        self.id = id
        self.name = name
        self.template = template
    }

    var requiresArgument: Bool { template.contains("{query}") }

    func resolvedURL(argument: String?) -> URL? {
        guard requiresArgument else { return URL(string: template) }
        guard let argument, !argument.isEmpty else { return nil }
        let encoded = argument.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? argument
        return URL(string: template.replacingOccurrences(of: "{query}", with: encoded))
    }
}

@MainActor
final class QuicklinkStore: ObservableObject {
    private static let storageKey = "launcher.quicklinks"

    @Published private(set) var quicklinks: [Quicklink] {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Quicklink].self, from: data) {
            quicklinks = decoded
        } else {
            quicklinks = []
        }
    }

    func add(_ quicklink: Quicklink) {
        quicklinks.append(quicklink)
    }

    func update(_ quicklink: Quicklink) {
        guard let index = quicklinks.firstIndex(where: { $0.id == quicklink.id }) else { return }
        quicklinks[index] = quicklink
    }

    func remove(id: UUID) {
        quicklinks.removeAll { $0.id == id }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(quicklinks) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Quicklinks whose name matches the query head; the remainder becomes the argument.
    func makeItems(query: String) -> [LauncherItem] {
        let (head, remainder) = LauncherQueryParser.split(query)
        return quicklinks.compactMap { quicklink in
            let matches = head.isEmpty
                || quicklink.name.localizedCaseInsensitiveContains(head)
                || quicklink.name.lowercased().hasPrefix(head.lowercased())
            guard matches else { return nil }
            let argument = remainder.isEmpty ? nil : remainder
            let subtitle: String
            if quicklink.requiresArgument {
                subtitle = argument.map { "Open with \"\($0)\"" } ?? "Type an argument…"
            } else {
                subtitle = quicklink.template
            }
            return LauncherItem(
                id: "Quicklink|\(quicklink.name)",
                title: quicklink.name,
                subtitle: subtitle,
                icon: .sfSymbol("link"),
                keywords: [quicklink.name],
                category: "Quicklinks",
                actions: [
                    LauncherAction(id: "open", title: "Open", systemImage: "arrow.up.right.square", shortcutHint: "↵") {
                        if let url = quicklink.resolvedURL(argument: argument) {
                            NSWorkspace.shared.open(url)
                            return .dismiss
                        }
                        return .stay
                    },
                ],
                acceptsArgument: quicklink.requiresArgument
            )
        }
    }
}
