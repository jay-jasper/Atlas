import AppKit
import Foundation

struct AppEntry: Sendable {
    let name: String
    let url: URL
}

final class AppLauncherProvider: CommandProviding, @unchecked Sendable {
    // Constants for Scoring and Limits
    private static let exactPrefixBaseScore = 1000
    private static let maxPrefixLengthBonus = 100
    private static let containsMatchScore = 500
    private static let fuzzyMatchBaseScore = 100
    private static let consecutiveMatchBonus = 10
    private static let maxResultsCount = 5

    private let lock = NSLock()
    private var _apps: [AppEntry] = []
    
    private var apps: [AppEntry] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _apps
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _apps = newValue
        }
    }

    init(apps: [AppEntry]? = nil) {
        if let apps {
            self._apps = apps
        } else {
            Task.detached(priority: .utility) { [weak self] in
                let scanned = Self.scanApplications()
                self?.apps = scanned
            }
        }
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        let scored = apps.compactMap { app -> (AppEntry, Int)? in
            let score = Self.fuzzyScore(query: q, in: app.name)
            return score > 0 ? (app, score) : nil
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(Self.maxResultsCount)
            .map { entry, _ in
                PaletteCommand(
                    id: UUID(),
                    title: entry.name,
                    subtitle: nil,
                    icon: .appIcon(entry.url),
                    keywords: [],
                    action: .execute { NSWorkspace.shared.open(entry.url) },
                    category: "App"
                )
            }
    }

    static func fuzzyScore(query: String, in target: String) -> Int {
        let q = query.lowercased()
        let t = target.lowercased()

        guard !q.isEmpty else { return 0 }

        // Exact prefix: highest score
        if t.hasPrefix(q) { return exactPrefixBaseScore + (maxPrefixLengthBonus - t.count) }

        // Contains match: medium score
        if t.contains(q) { return containsMatchScore }

        // Fuzzy: all query chars must appear in order in target
        let qChars = Array(q)
        let tChars = Array(t)
        
        var qi = 0
        var consecutiveBonus = 0
        var lastMatchIndex: Int? = nil

        for ti in 0..<tChars.count {
            if tChars[ti] == qChars[qi] {
                if let last = lastMatchIndex, last + 1 == ti {
                    consecutiveBonus += consecutiveMatchBonus
                }
                lastMatchIndex = ti
                qi += 1
                if qi == qChars.count {
                    break // Early exit: all query characters matched!
                }
            }
        }

        guard qi == qChars.count else { return 0 }
        return fuzzyMatchBaseScore + consecutiveBonus
    }

    private static func scanApplications() -> [AppEntry] {
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Applications")),
        ]
        
        var entries: [AppEntry] = []
        for dir in dirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }
            
            for url in contents where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                entries.append(AppEntry(name: name, url: url))
            }
        }
        
        // Deduplicate in case an app is present in multiple folders or scanned twice
        var seen = Set<URL>()
        var uniqueEntries: [AppEntry] = []
        for entry in entries {
            if !seen.contains(entry.url) {
                seen.insert(entry.url)
                uniqueEntries.append(entry)
            }
        }
        
        return uniqueEntries.sorted { $0.name < $1.name }
    }
}
