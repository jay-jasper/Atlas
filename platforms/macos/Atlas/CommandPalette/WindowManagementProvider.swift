import Foundation

final class WindowManagementProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let windowManager: WindowManaging
    private let actions: [WindowManagementAction]
    private let isEnabled: () -> Bool

    init(
        windowManager: WindowManaging = AccessibilityWindowManager(),
        actions: [WindowManagementAction] = WindowManagementAction.commandPaletteActions,
        isEnabled: @escaping () -> Bool = { true }
    ) {
        self.windowManager = windowManager
        self.actions = actions
        self.isEnabled = isEnabled
    }

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return actions
            .filter { action in
                action.title.localizedCaseInsensitiveContains(q) ||
                action.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
            }
            .prefix(Self.maxResultsCount)
            .map { [windowManager] action in
                PaletteCommand(
                    id: UUID(),
                    title: action.title,
                    subtitle: nil,
                    icon: .sfSymbol("rectangle.inset.filled"),
                    keywords: action.keywords,
                    action: .execute { _ = windowManager.perform(action) },
                    category: "Window"
                )
            }
    }
}
