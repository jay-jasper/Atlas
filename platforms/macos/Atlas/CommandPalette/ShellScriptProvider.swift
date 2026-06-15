import Foundation

/// Runs user-registered shell scripts: `run <script-name>`. Scripts are stored
/// in settings and executed via `/bin/zsh -c`. Lists matching scripts; the
/// selected one is run in the background.
final class ShellScriptProvider: CommandProviding {
    private let store: ShellScriptStoring
    private let execute: (ShellScript) -> Void
    private static let maxResults = 6

    init(
        store: ShellScriptStoring = ShellScriptStore(),
        execute: @escaping (ShellScript) -> Void = ShellScriptProvider.runInBackground
    ) {
        self.store = store
        self.execute = execute
    }

    func results(for query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower == "run" || lower.hasPrefix("run ") else { return [] }
        let term = lower == "run" ? "" : String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)

        let scripts = store.scripts()
        let matches = term.isEmpty
            ? scripts
            : scripts.filter { $0.name.lowercased().contains(term.lowercased()) }

        return matches.prefix(Self.maxResults).map { script in
            PaletteCommand(
                id: UUID(),
                title: "Run \(script.name)",
                subtitle: String(script.body.prefix(60)),
                icon: .sfSymbol("terminal"),
                keywords: ["run", "script", "shell", script.name.lowercased()],
                action: .execute { [execute] in execute(script) },
                category: "Scripts"
            )
        }
    }

    static func runInBackground(_ script: ShellScript) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script.body]
        try? process.run()
    }
}
