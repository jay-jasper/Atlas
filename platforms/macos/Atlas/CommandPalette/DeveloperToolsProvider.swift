import AppKit
import Foundation

final class DeveloperToolsProvider: CommandProviding {
    private static let maxResultsCount = 5

    private struct DeveloperCommand {
        let title: String
        let keywords: [String]
        let action: () -> Void
    }

    private let commands: [DeveloperCommand]

    init(
        openTerminal: @escaping () -> Void = {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        },
        openActivityMonitor: @escaping () -> Void = {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        },
        openConsole: @escaping () -> Void = {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
        }
    ) {
        commands = [
            DeveloperCommand(
                title: "Open Terminal",
                keywords: ["developer", "dev", "terminal", "shell", "command line"],
                action: openTerminal
            ),
            DeveloperCommand(
                title: "Open Activity Monitor",
                keywords: ["developer", "dev", "activity", "monitor", "processes", "system"],
                action: openActivityMonitor
            ),
            DeveloperCommand(
                title: "Open Console",
                keywords: ["developer", "dev", "console", "logs", "system log"],
                action: openConsole
            ),
        ]
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return commands
            .filter { command in
                command.title.localizedCaseInsensitiveContains(q) ||
                command.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
            }
            .prefix(Self.maxResultsCount)
            .map { command in
                PaletteCommand(
                    id: UUID(),
                    title: command.title,
                    subtitle: nil,
                    icon: .sfSymbol("hammer"),
                    keywords: command.keywords,
                    action: .execute(command.action),
                    category: "Developer"
                )
            }
    }
}
