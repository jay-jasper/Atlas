import AppKit
import Foundation

/// Searches the Raycast-v2-style Rust file index directly, no prefix needed
/// (legacy `f <name>` still works).
/// Opens the file (or reveals in Finder with the secondary path) on selection.
final class FileSearchProvider: CommandProviding, AsyncCommandProviding {
    private let open: (String) -> Void
    private let syncSearch: (String, Int) -> [String]
    private let asyncSearch: @Sendable (String, Int) async -> [String]
    private static let maxResults = 6
    private static let maxIndexCandidates = 128

    init(
        open: @escaping (String) -> Void = { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) },
        syncSearch: ((String, Int) -> [String])? = nil,
        asyncSearch: (@Sendable (String, Int) async -> [String])? = nil
    ) {
        self.open = open
        self.syncSearch = syncSearch ?? { term, limit in
            RaycastV2Search.searchFiles(query: term, limit: limit)
        }
        self.asyncSearch = asyncSearch ?? { term, limit in
            await Task.detached(priority: .userInitiated) {
                RaycastV2Search.searchFiles(query: term, limit: limit)
            }.value
        }
    }

    func results(for query: String) -> [PaletteCommand] {
        let term = Self.term(from: query)
        guard term.count >= 3 else { return [] }

        let paths = syncSearch(term, Self.maxIndexCandidates)
        return makeCommands(paths: Self.rank(paths: paths, term: term), term: term)
    }

    func resultsAsync(for query: String) async -> [PaletteCommand] {
        let term = Self.term(from: query)
        guard term.count >= 3 else { return [] }

        let paths = await asyncSearch(term, Self.maxIndexCandidates)
        guard !Task.isCancelled else { return [] }
        return makeCommands(paths: Self.rank(paths: paths, term: term), term: term)
    }

    private func makeCommands<S: Sequence>(paths: S, term: String) -> [PaletteCommand]
    where S.Element == String {
        paths.prefix(Self.maxResults).map { path in
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

    private static func term(from query: String) -> String {
        var term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.lowercased().hasPrefix("f ") {
            term = String(term.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return term
    }

    /// 索引结果保持稳定二次排序:前缀 > 包含 > 其他,同级短名靠前。
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
