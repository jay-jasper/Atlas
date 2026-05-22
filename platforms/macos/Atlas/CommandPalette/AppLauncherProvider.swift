import AppKit
import Foundation

struct AppEntry: Equatable, Sendable {
    let name: String
    let url: URL
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
}
