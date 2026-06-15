import AppKit
import Foundation

struct InstalledBrowser: Equatable, Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

@MainActor
final class BrowserRouterService: ObservableObject {
    @Published private(set) var routes: [BrowserRoute] = []
    @Published var testURL: String = ""
    @Published private(set) var testResult: String = ""

    private let store: BrowserRouteStoring
    let installedBrowsers: [InstalledBrowser]
    var defaultBrowserBundleID: String

    init(
        store: BrowserRouteStoring = BrowserRouteStore(),
        installedBrowsers: [InstalledBrowser]? = nil,
        defaultBrowserBundleID: String = "com.apple.Safari"
    ) {
        self.store = store
        self.installedBrowsers = installedBrowsers ?? Self.discoverBrowsers()
        self.defaultBrowserBundleID = defaultBrowserBundleID
        reload()
    }

    func reload() {
        routes = store.routes()
    }

    func addRoute(pattern: String, browser: InstalledBrowser) {
        guard !pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        try? store.upsert(BrowserRoute(pattern: pattern, browserBundleID: browser.bundleID, browserName: browser.name))
        reload()
    }

    func delete(id: UUID) {
        try? store.delete(id: id)
        reload()
    }

    func resolve(_ url: String) -> String {
        BrowserRouter.resolve(url: url, rules: routes, defaultBrowserBundleID: defaultBrowserBundleID)
    }

    func runTest() {
        guard !testURL.isEmpty else { testResult = ""; return }
        let bundleID = resolve(testURL)
        let name = installedBrowsers.first { $0.bundleID == bundleID }?.name ?? bundleID
        testResult = "Opens in: \(name)"
    }

    /// Opens a URL in the routed browser.
    func open(_ url: URL) {
        let bundleID = resolve(url.absoluteString)
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSWorkspace.shared.open(url)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
    }

    static func discoverBrowsers() -> [InstalledBrowser] {
        let candidates: [(String, String)] = [
            ("com.apple.Safari", "Safari"),
            ("com.google.Chrome", "Chrome"),
            ("org.mozilla.firefox", "Firefox"),
            ("company.thebrowser.Browser", "Arc"),
            ("com.microsoft.edgemac", "Edge"),
            ("com.brave.Browser", "Brave"),
        ]
        return candidates.compactMap { bundleID, name in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
                ? InstalledBrowser(bundleID: bundleID, name: name)
                : nil
        }
    }
}
