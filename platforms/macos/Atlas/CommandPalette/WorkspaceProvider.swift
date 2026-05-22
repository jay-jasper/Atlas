import Foundation

final class WorkspaceProvider: CommandProviding {
    private let store: WorkspaceStoring
    private let isEnabled: () -> Bool
    private let onSaveCurrent: () -> Void
    private let onRestore: (Workspace) -> Void

    init(
        store: WorkspaceStoring,
        isEnabled: @escaping () -> Bool,
        onSaveCurrent: @escaping () -> Void = {},
        onRestore: @escaping (Workspace) -> Void = { _ in }
    ) {
        self.store = store
        self.isEnabled = isEnabled
        self.onSaveCurrent = onSaveCurrent
        self.onRestore = onRestore
    }

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var commands = fixedCommands().filter { command in
            command.title.localizedCaseInsensitiveContains(q) ||
                command.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }

        let workspaceCommands = (try? store.load())?.filter { workspace in
            workspace.name.localizedCaseInsensitiveContains(q) || q.localizedCaseInsensitiveContains("workspace")
        }.map { workspace in
            PaletteCommand(
                id: UUID(),
                title: "Restore Workspace: \(workspace.name)",
                subtitle: "\(workspace.windows.count) windows",
                icon: .sfSymbol("macwindow.on.rectangle"),
                keywords: ["workspace", "restore", workspace.name],
                action: .execute { [onRestore] in onRestore(workspace) },
                category: "Workspace"
            )
        } ?? []

        commands.append(contentsOf: workspaceCommands)
        return Array(commands.prefix(8))
    }

    private func fixedCommands() -> [PaletteCommand] {
        [
            PaletteCommand(
                id: UUID(),
                title: "Open Workspaces",
                subtitle: nil,
                icon: .sfSymbol("rectangle.3.group"),
                keywords: ["workspace", "open", "panel"],
                action: .push(.workspaces),
                category: "Workspace"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Save Current Workspace",
                subtitle: nil,
                icon: .sfSymbol("square.and.arrow.down"),
                keywords: ["workspace", "save", "current", "layout"],
                action: .execute { [onSaveCurrent] in onSaveCurrent() },
                category: "Workspace"
            ),
        ]
    }
}
