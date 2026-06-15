import AppKit
import Foundation

/// Searches files by name via Spotlight (`mdfind`): `f <name>`. Opens the file
/// (or reveals in Finder with the secondary path) on selection.
final class FileSearchProvider: CommandProviding {
    private let commandRunner: SystemCommandRunning
    private let open: (String) -> Void
    private static let maxResults = 6

    init(
        commandRunner: SystemCommandRunning = LiveSystemCommandRunner(),
        open: @escaping (String) -> Void = { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) }
    ) {
        self.commandRunner = commandRunner
        self.open = open
    }

    func results(for query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("f ") else { return [] }
        let term = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { return [] }

        let paths = Self.search(term: term, runner: commandRunner)
        return paths.prefix(Self.maxResults).map { path in
            let url = URL(fileURLWithPath: path)
            return PaletteCommand(
                id: UUID(),
                title: url.lastPathComponent,
                subtitle: path,
                icon: .sfSymbol("doc"),
                keywords: ["file", "search", "find", term],
                action: .execute { [open] in open(path) },
                category: "Files"
            )
        }
    }

    static func search(term: String, runner: SystemCommandRunning) -> [String] {
        guard let result = try? runner.run(
            "/usr/bin/mdfind",
            arguments: ["-name", term]
        ), result.succeeded else { return [] }
        return result.standardOutput
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
