import Foundation

struct AppLeftover: Equatable, Identifiable {
    var id: String { path }
    let category: String
    let path: String
    let size: Int64
}

/// Derives the set of support files a macOS app typically leaves behind, from
/// its name and bundle identifier. Path derivation is pure and testable; the
/// existence/size probe is delegated to an injected file prober.
enum AppLeftoverFinder {
    /// Library subpaths checked for an app's leftovers, with display categories.
    static func candidatePaths(home: URL, appName: String, bundleID: String?) -> [(category: String, url: URL)] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        var results: [(String, URL)] = []

        func add(_ category: String, _ relative: String) {
            results.append((category, library.appendingPathComponent(relative)))
        }

        if let bundleID, !bundleID.isEmpty {
            add("Application Support", "Application Support/\(bundleID)")
            add("Caches", "Caches/\(bundleID)")
            add("Preferences", "Preferences/\(bundleID).plist")
            add("Containers", "Containers/\(bundleID)")
            add("Saved State", "Saved Application State/\(bundleID).savedState")
            add("Group Containers", "Group Containers/\(bundleID)")
            add("HTTP Storage", "HTTPStorages/\(bundleID)")
            add("Logs", "Logs/\(bundleID)")
        }
        if !appName.isEmpty {
            add("Application Support", "Application Support/\(appName)")
            add("Caches", "Caches/\(appName)")
            add("Logs", "Logs/\(appName)")
        }
        return results
    }

    /// Probes the candidate paths, returning those that exist with their sizes.
    static func find(
        home: URL,
        appName: String,
        bundleID: String?,
        prober: (URL) -> Int64?
    ) -> [AppLeftover] {
        var seen = Set<String>()
        var leftovers: [AppLeftover] = []
        for (category, url) in candidatePaths(home: home, appName: appName, bundleID: bundleID) {
            guard !seen.contains(url.path) else { continue }
            seen.insert(url.path)
            if let size = prober(url) {
                leftovers.append(AppLeftover(category: category, path: url.path, size: size))
            }
        }
        return leftovers.sorted { $0.size > $1.size }
    }
}
