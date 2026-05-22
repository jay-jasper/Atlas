import Foundation

final class CustomAutomationProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let store: CustomAutomationStoring
    private let isEnabled: () -> Bool

    init(
        store: CustomAutomationStoring = CustomAutomationStore(),
        isEnabled: @escaping () -> Bool
    ) {
        self.store = store
        self.isEnabled = isEnabled
    }

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return store.commands()
            .filter { command in
                command.title.localizedCaseInsensitiveContains(trimmed)
                    || command.command.localizedCaseInsensitiveContains(trimmed)
                    || command.kind.title.localizedCaseInsensitiveContains(trimmed)
                    || command.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
            .prefix(Self.maxResultsCount)
            .map { command in
                PaletteCommand(
                    id: command.id,
                    title: "Run \(command.title)",
                    subtitle: "\(command.kind.title) automation",
                    icon: .sfSymbol(command.kind == .python ? "curlybraces" : "terminal"),
                    keywords: command.keywords + [command.kind.rawValue, "automation", "run"],
                    action: .push(.automationOutput(command)),
                    category: "Automation"
                )
            }
    }
}
