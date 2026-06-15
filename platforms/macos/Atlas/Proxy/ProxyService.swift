import Foundation

protocol ProxyProfileStoring {
    func profiles() -> [ProxyProfile]
    func save(_ profiles: [ProxyProfile]) throws
}

final class ProxyProfileStore: ProxyProfileStoring {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = ProxyProfileStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func profiles() -> [ProxyProfile] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([ProxyProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [ProxyProfile]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(profiles).write(to: fileURL, options: [.atomic])
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("proxy-profiles.json")
    }
}

final class InMemoryProxyProfileStore: ProxyProfileStoring {
    private var store: [ProxyProfile]
    init(profiles: [ProxyProfile] = []) { store = profiles }
    func profiles() -> [ProxyProfile] { store }
    func save(_ profiles: [ProxyProfile]) throws { store = profiles }
}

@MainActor
final class ProxyService: ObservableObject {
    @Published private(set) var profiles: [ProxyProfile] = []
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var statusMessage: String = ""

    /// The primary network service (e.g. "Wi-Fi"); resolved at runtime.
    var networkService: String = "Wi-Fi"
    private let store: ProxyProfileStoring
    private let runner: SystemCommandRunning

    init(store: ProxyProfileStoring = ProxyProfileStore(), runner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.store = store
        self.runner = runner
        reload()
    }

    func reload() {
        profiles = store.profiles()
    }

    func add(_ profile: ProxyProfile) {
        guard profile.isValid else {
            statusMessage = "Profile requires a name, host, and valid port."
            return
        }
        var updated = profiles
        updated.append(profile)
        try? store.save(updated)
        statusMessage = ""
        reload()
    }

    func delete(id: UUID) {
        try? store.save(profiles.filter { $0.id != id })
        if activeProfileID == id { activeProfileID = nil }
        reload()
    }

    func apply(_ profile: ProxyProfile) {
        do {
            _ = try runner.run("/usr/sbin/networksetup", arguments: ProxyCommandBuilder.setCommand(profile, networkService: networkService))
            _ = try runner.run("/usr/sbin/networksetup", arguments: ProxyCommandBuilder.enableCommand(profile.kind, networkService: networkService, on: true))
            activeProfileID = profile.id
            statusMessage = "Applied \(profile.name)."
        } catch {
            statusMessage = "Failed to apply proxy — administrator privilege may be required."
        }
    }

    func disableAll() {
        for kind in ProxyKind.allCases {
            _ = try? runner.run("/usr/sbin/networksetup", arguments: ProxyCommandBuilder.enableCommand(kind, networkService: networkService, on: false))
        }
        activeProfileID = nil
        statusMessage = "Proxies disabled."
    }
}
