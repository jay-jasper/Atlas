import AppKit
import Foundation

struct AppEntry: Equatable, Sendable {
    let name: String
    let url: URL
    /// 本地化显示名(如 WeChat → 微信);中文系统下搜中文靠它。
    var localizedName: String = ""

    var displayName: String { localizedName.isEmpty ? name : localizedName }
}

final class AppLauncherProvider: CommandProviding, @unchecked Sendable {
    private static let exactPrefixBaseScore = 1000
    private static let maxPrefixLengthBonus = 100
    private static let containsMatchScore = 500
    private static let fuzzyMatchBaseScore = 100
    private static let consecutiveMatchBonus = 10
    private static let maxResultsCount = 5

    private let lock = NSLock()
    private let refreshLock = NSLock()
    private let scanner: ApplicationScanning?
    private let changeObserver: ApplicationChangeObserving?
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

    convenience init() {
        self.init(
            scanner: FileSystemApplicationScanner(),
            changeObserver: ApplicationDirectoryChangeObserver(),
            refreshOnInit: false
        )
        Task.detached(priority: .utility) { [weak self] in
            self?.refreshApplications()
        }
    }

    convenience init(
        scanner: ApplicationScanning,
        changeObserver: ApplicationChangeObserving? = ApplicationDirectoryChangeObserver()
    ) {
        self.init(scanner: scanner, changeObserver: changeObserver, refreshOnInit: true)
    }

    init(
        apps: [AppEntry],
        changeObserver: ApplicationChangeObserving? = nil
    ) {
        self._apps = apps
        self.scanner = nil
        self.changeObserver = nil
    }

    private init(
        scanner: ApplicationScanning,
        changeObserver: ApplicationChangeObserving?,
        refreshOnInit: Bool
    ) {
        self.scanner = scanner
        self.changeObserver = changeObserver
        if refreshOnInit {
            refreshApplications()
        }
        changeObserver?.setChangeHandler { [weak self] in
            self?.refreshApplications()
        }
        changeObserver?.start()
    }

    deinit {
        changeObserver?.stop()
    }

    func refreshApplications() {
        guard let scanner else { return }
        refreshLock.lock()
        defer { refreshLock.unlock() }

        let refreshedApps = scanner.scanApplications()
        apps = refreshedApps
    }

    private func ensureApplicationsLoaded() {
        guard let scanner, apps.isEmpty else { return }
        refreshLock.lock()
        defer { refreshLock.unlock() }
        guard apps.isEmpty else { return }
        apps = scanner.scanApplications()
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        // The initial scan is intentionally off-main-thread. If the first launcher
        // query wins that race, finish the scan here (the coordinator calls us from
        // its detached collection task) instead of returning an empty app section.
        ensureApplicationsLoaded()
        let appSnapshot = apps

        let appsByID = Dictionary(uniqueKeysWithValues: appSnapshot.map {
            ($0.url.path, $0)
        })
        let documents = appSnapshot.map { app in
            var keywords = [app.name]
            if app.displayName != app.name {
                keywords.append(app.displayName)
            }
            keywords.append(contentsOf: RaycastV2Search.searchAliases(for: app.name))
            keywords.append(contentsOf: RaycastV2Search.searchAliases(for: app.displayName))
            return SearchDocumentInput(
                id: app.url.path,
                namespace: "apps",
                title: app.displayName,
                subtitle: app.name == app.displayName ? "" : app.name,
                keywords: keywords,
                path: app.url.path,
                kind: "application",
                modifiedAt: 0
            )
        }
        let ranked = RaycastV2Search.rank(
            query: q,
            documents: documents,
            limit: Self.maxResultsCount
        )

        return ranked.compactMap { appsByID[$0.id] }
            .map { entry in
                PaletteCommand(
                    id: UUID(),
                    title: entry.displayName,
                    subtitle: nil,
                    icon: .appIcon(entry.url),
                    keywords: entry.displayName == entry.name ? [] : [entry.name],
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

        // Fuzzy matches stay within one app-name word. Allowing a match to jump
        // between words makes unrelated queries such as "test" match
        // "System Settings" ("SysTem SEtTings").
        let words = t.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let bestWordScore = words
            .map { fuzzySubsequenceScore(query: q, candidate: $0) }
            .max() ?? 0
        if bestWordScore > 0 {
            return bestWordScore
        }

        // Initials preserve the common multi-word shortcut ("ss" →
        // "System Settings") without reintroducing arbitrary cross-word jumps.
        let initials = String(words.compactMap(\.first))
        guard initials.hasPrefix(q) else { return 0 }
        return fuzzyMatchBaseScore + q.count * consecutiveMatchBonus
    }

    private static func fuzzySubsequenceScore(query: String, candidate: String) -> Int {
        let qChars = Array(query)
        let tChars = Array(candidate)

        var qi = 0
        var consecutiveBonus = 0
        var lastMatchIndex: Int? = nil
        var firstMatchIndex: Int?

        for ti in 0..<tChars.count {
            if tChars[ti] == qChars[qi] {
                if firstMatchIndex == nil {
                    firstMatchIndex = ti
                }
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

        guard qi == qChars.count,
              let firstMatchIndex,
              let lastMatchIndex,
              lastMatchIndex - firstMatchIndex + 1 <= qChars.count * 2 + 1 else {
            return 0
        }
        return fuzzyMatchBaseScore + consecutiveBonus
    }
}
