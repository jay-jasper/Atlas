import AppKit
import Foundation

/// Searches files by name via Spotlight (`mdfind`) — Raycast style: any query
/// searches files directly, no prefix needed (legacy `f <name>` still works).
/// Opens the file (or reveals in Finder with the secondary path) on selection.
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
        var term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.lowercased().hasPrefix("f ") {
            term = String(term.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        guard term.count >= 2 else { return [] }

        let paths = Self.search(term: term, runner: commandRunner)
        return Self.rank(paths: paths, term: term).prefix(Self.maxResults).map { path in
            let url = URL(fileURLWithPath: path)
            return PaletteCommand(
                id: UUID(),
                title: url.lastPathComponent,
                subtitle: path,
                icon: .appIcon(url),
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

    /// mdfind 输出无序;按文件名命中质量排:前缀 > 包含 > 其他,同级短名靠前。
    /// .app 交给应用搜索,这里剔除避免重复行。
    static func rank(paths: [String], term: String) -> [String] {
        let lowerTerm = term.lowercased()
        return paths
            .filter { !$0.hasSuffix(".app") }
            .map { path -> (String, Int, Int) in
                let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
                let tier: Int
                if name.hasPrefix(lowerTerm) {
                    tier = 0
                } else if name.contains(lowerTerm) {
                    tier = 1
                } else {
                    tier = 2
                }
                return (path, tier, name.count)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
                return lhs.0 < rhs.0
            }
            .map(\.0)
    }
}
