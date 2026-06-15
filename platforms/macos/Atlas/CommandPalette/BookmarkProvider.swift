import AppKit
import Foundation

struct Bookmark: Equatable {
    let title: String
    let url: String
    let source: String
}

/// Searches browser bookmarks (Chrome/Edge/Brave JSON stores) and opens the URL
/// on selection. Auto-searches when the query (3+ chars) matches a title; no
/// keyword required. Bookmarks are loaded once and cached.
final class BookmarkProvider: CommandProviding {
    private let loader: () -> [Bookmark]
    private let open: (String) -> Void
    private lazy var bookmarks: [Bookmark] = loader()
    private static let maxResults = 5

    init(
        loader: @escaping () -> [Bookmark] = { BookmarkProvider.loadAll() },
        open: @escaping (String) -> Void = { urlString in
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
        }
    ) {
        self.loader = loader
        self.open = open
    }

    func results(for query: String) -> [PaletteCommand] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard term.count >= 3 else { return [] }

        return bookmarks
            .filter { $0.title.lowercased().contains(term) || $0.url.lowercased().contains(term) }
            .prefix(Self.maxResults)
            .map { bookmark in
                PaletteCommand(
                    id: UUID(),
                    title: bookmark.title,
                    subtitle: "\(bookmark.source) · \(bookmark.url)",
                    icon: .sfSymbol("bookmark"),
                    keywords: ["bookmark", bookmark.source.lowercased()],
                    action: .execute { [open] in open(bookmark.url) },
                    category: "Bookmarks"
                )
            }
    }

    // MARK: - Loading

    static func loadAll(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Bookmark] {
        let chromiumStores: [(String, String)] = [
            ("Chrome", "Library/Application Support/Google/Chrome/Default/Bookmarks"),
            ("Edge", "Library/Application Support/Microsoft Edge/Default/Bookmarks"),
            ("Brave", "Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks"),
        ]
        var all: [Bookmark] = []
        for (name, relativePath) in chromiumStores {
            let url = home.appendingPathComponent(relativePath)
            if let data = try? Data(contentsOf: url) {
                all.append(contentsOf: parseChromium(data, source: name))
            }
        }
        return all
    }

    /// Parses a Chromium `Bookmarks` JSON file into flat bookmark entries.
    static func parseChromium(_ data: Data, source: String) -> [Bookmark] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else {
            return []
        }
        var result: [Bookmark] = []
        for value in roots.values {
            if let node = value as? [String: Any] {
                collect(node, source: source, into: &result)
            }
        }
        return result
    }

    private static func collect(_ node: [String: Any], source: String, into result: inout [Bookmark]) {
        if let type = node["type"] as? String {
            if type == "url", let name = node["name"] as? String, let url = node["url"] as? String {
                result.append(Bookmark(title: name, url: url, source: source))
            } else if type == "folder", let children = node["children"] as? [[String: Any]] {
                for child in children { collect(child, source: source, into: &result) }
            }
        } else if let children = node["children"] as? [[String: Any]] {
            for child in children { collect(child, source: source, into: &result) }
        }
    }
}
