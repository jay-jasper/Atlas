import CryptoKit
import Foundation

/// A descriptor for an installed plugin and the Block Kit UI it currently emits.
struct PluginDescriptor: Equatable, Identifiable {
    var id: String { "\(name)@\(version)" }
    let name: String
    let version: String
    let track: String
    let ui: BlockKitNode
}

protocol PluginRuntimeProviding: Sendable {
    func inspectManifest(_ manifest: String) throws -> PluginInstallPreview
    func installWasm(manifest: String, bytes: Data, uiJSON: String) throws -> PluginEntry
    func installMCP(manifest: String, uiJSON: String) throws -> PluginEntry
    func installJS(manifest: String, source: String, uiJSON: String) throws -> PluginEntry
    func list() throws -> [PluginEntry]
    func uninstall(id: String) throws -> Bool
    func dispatch(id: String, eventJSON: String) throws -> String
}

struct LivePluginRuntime: PluginRuntimeProviding {
    func inspectManifest(_ manifest: String) throws -> PluginInstallPreview {
        try Atlas.inspectPluginManifest(manifestToml: manifest)
    }

    func installWasm(manifest: String, bytes: Data, uiJSON: String) throws -> PluginEntry {
        try Atlas.installWasmPlugin(manifestToml: manifest, wasmBytes: Array(bytes), uiJson: uiJSON)
    }

    func installMCP(manifest: String, uiJSON: String) throws -> PluginEntry {
        try Atlas.installMcpPlugin(manifestToml: manifest, uiJson: uiJSON)
    }

    func installJS(manifest: String, source: String, uiJSON: String) throws -> PluginEntry {
        try Atlas.installJsPlugin(manifestToml: manifest, source: source, uiJson: uiJSON)
    }

    func list() throws -> [PluginEntry] {
        try Atlas.listPlugins()
    }

    func uninstall(id: String) throws -> Bool {
        try Atlas.uninstallPlugin(id: id)
    }

    func dispatch(id: String, eventJSON: String) throws -> String {
        try Atlas.dispatchPluginEvent(id: id, eventJson: eventJSON)
    }
}

protocol PluginPackagePathStoring {
    func loadPaths() -> [String]
    func savePaths(_ paths: [String])
    func loadConsentFingerprints() -> [String: String]
    func saveConsentFingerprints(_ fingerprints: [String: String])
}

extension PluginPackagePathStoring {
    func loadConsentFingerprints() -> [String: String] { [:] }
    func saveConsentFingerprints(_: [String: String]) {}
}

struct PluginPackagePathStore: PluginPackagePathStoring {
    private let defaults: UserDefaults
    private let key: String
    private let consentKey: String

    init(defaults: UserDefaults = .standard, key: String = "atlas.pluginPackagePaths.v1") {
        self.defaults = defaults
        self.key = key
        consentKey = "\(key).consents"
    }

    func loadPaths() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    func savePaths(_ paths: [String]) {
        defaults.set(paths, forKey: key)
    }

    func loadConsentFingerprints() -> [String: String] {
        defaults.dictionary(forKey: consentKey) as? [String: String] ?? [:]
    }

    func saveConsentFingerprints(_ fingerprints: [String: String]) {
        defaults.set(fingerprints, forKey: consentKey)
    }
}

struct PendingPluginInstall: Identifiable {
    let packageURL: URL
    let manifest: String
    let preview: PluginInstallPreview

    var id: String { packageURL.path }

    var title: String { "Install \(preview.name) \(preview.version)?" }

    var consentMessage: String {
        var requests: [String] = []
        if !preview.networkHosts.isEmpty {
            requests.append("Network access: \(preview.networkHosts.joined(separator: ", "))")
        }
        if preview.storage { requests.append("Persistent plugin storage") }
        if preview.clipboard { requests.append("Read and write the clipboard") }
        if preview.webview { requests.append("Display web content") }
        if preview.webviewBridge { requests.append("Allow web content to call the plugin") }
        if !preview.exposedTools.isEmpty {
            requests.append("Expose MCP tools: \(preview.exposedTools.joined(separator: ", "))")
        }
        if requests.isEmpty {
            return "This plugin requests no privileged capabilities. Only install plugins you trust."
        }
        return "This plugin requests:\n\n• " + requests.joined(separator: "\n• ")
            + "\n\nOnly install plugins you trust."
    }
}

enum PluginPackageError: LocalizedError {
    case missingManifest
    case missingUI
    case packageTooLarge
    case invalidUI

    var errorDescription: String? {
        switch self {
        case .missingManifest: "Plugin package is missing plugin.toml."
        case .missingUI: "Plugin package is missing ui.json."
        case .packageTooLarge: "Plugin WASM module exceeds the 16 MB package limit."
        case .invalidUI: "Plugin emitted invalid Block Kit JSON."
        }
    }
}

@MainActor
final class PluginsService: ObservableObject {
    @Published private(set) var plugins: [PluginDescriptor] = []
    @Published private(set) var lastEvent: BlockKitEvent?
    @Published private(set) var statusMessage = ""
    @Published private(set) var lastRuntimeResponse: String?
    @Published var pendingInstallation: PendingPluginInstall?

    private let runtime: any PluginRuntimeProviding
    private let packageStore: any PluginPackagePathStoring
    private let allowsExecutablePlugins: Bool
    private var packagePathByPluginID: [String: String] = [:]
    private var consentFingerprintByPath: [String: String] = [:]

    init(
        runtime: any PluginRuntimeProviding = LivePluginRuntime(),
        packageStore: any PluginPackagePathStoring = PluginPackagePathStore(),
        allowsExecutablePlugins: Bool = DistributionPolicy.allowsExecutablePlugins
    ) {
        self.runtime = runtime
        self.packageStore = packageStore
        self.allowsExecutablePlugins = allowsExecutablePlugins
        restorePackages()
        refresh()
    }

    /// Local descriptor installation retained for previews/tests. Production
    /// package installation goes through `installPackage`, which invokes Rust.
    @discardableResult
    func install(name: String, version: String, track: String, uiJSON: String) -> Bool {
        guard let node = BlockKitNode.parse(uiJSON) else { return false }
        upsert(PluginDescriptor(name: name, version: version, track: track, ui: node))
        return true
    }

    @discardableResult
    func requestInstall(at packageURL: URL) -> Bool {
        do {
            guard allowsExecutablePlugins else {
                statusMessage = "Executable plugins are available in the direct distribution only."
                return false
            }
            let manifestURL = packageURL.appendingPathComponent("plugin.toml")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                throw PluginPackageError.missingManifest
            }
            let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
            let preview = try runtime.inspectManifest(manifest)
            pendingInstallation = PendingPluginInstall(
                packageURL: packageURL,
                manifest: manifest,
                preview: preview
            )
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func confirmPendingInstallation(_ pendingInstallation: PendingPluginInstall) {
        self.pendingInstallation = nil
        _ = installPackage(
            at: pendingInstallation.packageURL,
            expectedManifest: pendingInstallation.manifest
        )
    }

    func cancelPendingInstallation() {
        pendingInstallation = nil
        statusMessage = "Plugin installation cancelled."
    }

    @discardableResult
    func installPackage(
        at packageURL: URL,
        persist: Bool = true,
        expectedManifest: String? = nil
    ) -> Bool {
        do {
            guard allowsExecutablePlugins else {
                statusMessage = "Executable plugins are available in the direct distribution only."
                return false
            }
            let manifestURL = packageURL.appendingPathComponent("plugin.toml")
            let uiURL = packageURL.appendingPathComponent("ui.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                throw PluginPackageError.missingManifest
            }
            guard FileManager.default.fileExists(atPath: uiURL.path) else {
                throw PluginPackageError.missingUI
            }
            let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
            if let expectedManifest, manifest != expectedManifest {
                statusMessage = "The plugin manifest changed after permission review. Review it again before installing."
                return false
            }
            let uiJSON = try String(contentsOf: uiURL, encoding: .utf8)
            guard BlockKitNode.parse(uiJSON) != nil else { throw PluginPackageError.invalidUI }
            let files = try FileManager.default.contentsOfDirectory(
                at: packageURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let entry: PluginEntry
            if let wasmURL = files.first(where: { $0.pathExtension.lowercased() == "wasm" }) {
                let data = try Data(contentsOf: wasmURL, options: [.mappedIfSafe])
                guard data.count <= 16 * 1024 * 1024 else { throw PluginPackageError.packageTooLarge }
                entry = try runtime.installWasm(manifest: manifest, bytes: data, uiJSON: uiJSON)
            } else if let jsURL = files.first(where: { $0.pathExtension.lowercased() == "js" }) {
                let source = try String(contentsOf: jsURL, encoding: .utf8)
                guard source.utf8.count <= 2 * 1024 * 1024 else { throw PluginPackageError.packageTooLarge }
                entry = try runtime.installJS(manifest: manifest, source: source, uiJSON: uiJSON)
            } else {
                entry = try runtime.installMCP(manifest: manifest, uiJSON: uiJSON)
            }
            guard let descriptor = Self.map(entry) else { throw PluginPackageError.invalidUI }
            upsert(descriptor)
            packagePathByPluginID[entry.id] = packageURL.path
            consentFingerprintByPath[packageURL.path] = Self.manifestFingerprint(manifest)
            if persist {
                savePackageState()
            }
            statusMessage = "Installed \(entry.name) \(entry.version)."
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func uninstall(id: String) {
        do {
            _ = try runtime.uninstall(id: id)
            plugins.removeAll { $0.id == id }
            let removedPath = packagePathByPluginID[id]
            packagePathByPluginID.removeValue(forKey: id)
            if let removedPath {
                consentFingerprintByPath.removeValue(forKey: removedPath)
            }
            savePackageState()
            statusMessage = "Plugin removed."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func handle(_ event: BlockKitEvent, pluginID: String? = nil) {
        lastEvent = event
        guard let pluginID, let eventJSON = Self.eventJSON(event) else { return }
        let runtime = self.runtime
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> (String?, String?) in
                do {
                    return (try runtime.dispatch(id: pluginID, eventJSON: eventJSON), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            if let response = outcome.0 {
                self?.lastRuntimeResponse = response
            } else if let message = outcome.1 {
                self?.statusMessage = message
            }
        }
    }

    func refresh() {
        do {
            plugins = try runtime.list().compactMap(Self.map).sorted { $0.id < $1.id }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func restorePackages() {
        consentFingerprintByPath = packageStore.loadConsentFingerprints()
        var skippedChangedPackage = false
        for path in packageStore.loadPaths() {
            let manifestURL = URL(fileURLWithPath: path).appendingPathComponent("plugin.toml")
            guard let data = try? Data(contentsOf: manifestURL),
                  consentFingerprintByPath[path] == Self.manifestFingerprint(data)
            else {
                consentFingerprintByPath.removeValue(forKey: path)
                skippedChangedPackage = true
                continue
            }
            _ = installPackage(at: URL(fileURLWithPath: path), persist: false)
        }
        savePackageState()
        if skippedChangedPackage {
            statusMessage = "A plugin changed since permission approval and was not loaded. Reinstall it to review permissions."
        }
    }

    private func savePackageState() {
        let paths = Array(Set(packagePathByPluginID.values)).sorted()
        consentFingerprintByPath = consentFingerprintByPath.filter { paths.contains($0.key) }
        packageStore.savePaths(paths)
        packageStore.saveConsentFingerprints(consentFingerprintByPath)
    }

    private static func manifestFingerprint(_ manifest: String) -> String {
        manifestFingerprint(Data(manifest.utf8))
    }

    private static func manifestFingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func upsert(_ descriptor: PluginDescriptor) {
        plugins.removeAll { $0.name == descriptor.name }
        plugins.append(descriptor)
        plugins.sort { $0.id < $1.id }
    }

    private static func map(_ entry: PluginEntry) -> PluginDescriptor? {
        guard let node = BlockKitNode.parse(entry.uiJson) else { return nil }
        let track: String
        switch entry.runtime {
        case .wasm: track = "wasm"
        case .mcp: track = "mcp"
        case .js: track = "js"
        }
        return PluginDescriptor(
            name: entry.name,
            version: entry.version,
            track: track,
            ui: node
        )
    }

    private static func eventJSON(_ event: BlockKitEvent) -> String? {
        let object: [String: Any]
        switch event {
        case .buttonClick(let action):
            object = ["kind": "button-click", "action": action]
        case .textChanged(let id, let value):
            object = ["kind": "text-changed", "id": id, "value": value]
        case .toggleChanged(let id, let value):
            object = ["kind": "toggle-changed", "id": id, "value": value]
        case .sliderChanged(let id, let value):
            object = ["kind": "slider-changed", "id": id, "value": value]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
