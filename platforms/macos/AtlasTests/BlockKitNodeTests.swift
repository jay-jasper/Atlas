import XCTest
@testable import Atlas

@MainActor
final class BlockKitNodeTests: XCTestCase {
    func testDecodesNestedTree() {
        let json = """
        {"kind":"vstack","children":[
          {"kind":"text","value":"Hello"},
          {"kind":"button","label":"Run","action":"run"}
        ]}
        """
        let node = BlockKitNode.parse(json)
        XCTAssertEqual(node, .vstack([
            .text("Hello"),
            .button(label: "Run", action: "run"),
        ]))
    }

    func testDecodesAllLeafKinds() {
        XCTAssertEqual(BlockKitNode.parse(#"{"kind":"spacer"}"#), .spacer)
        XCTAssertEqual(BlockKitNode.parse(#"{"kind":"progress","value":0.5}"#), .progress(0.5))
        XCTAssertEqual(BlockKitNode.parse(#"{"kind":"toggle","id":"t","label":"On","value":true}"#),
                       .toggle(id: "t", label: "On", value: true))
        XCTAssertEqual(BlockKitNode.parse(#"{"kind":"slider","id":"s","value":2,"min":0,"max":10}"#),
                       .slider(id: "s", value: 2, min: 0, max: 10))
    }

    func testUnknownKindFallsBack() {
        XCTAssertEqual(BlockKitNode.parse(#"{"kind":"hologram"}"#), .unknown("hologram"))
    }

    func testCollectsActionIDs() {
        let node = BlockKitNode.parse("""
        {"kind":"hstack","children":[
          {"kind":"button","label":"A","action":"a"},
          {"kind":"section","title":"s","children":[{"kind":"button","label":"B","action":"b"}]}
        ]}
        """)
        XCTAssertEqual(node?.actionIDs, ["a", "b"])
    }

    func testInvalidJSONReturnsNil() {
        XCTAssertNil(BlockKitNode.parse("{not json"))
    }
}

@MainActor
final class PluginsServiceTests: XCTestCase {
    private let ui = #"{"kind":"vstack","children":[{"kind":"text","value":"hi"}]}"#

    func testInstallDecodesUI() {
        let service = PluginsService()
        XCTAssertTrue(service.install(name: "calc", version: "1.0.0", track: "wasm", uiJSON: ui))
        XCTAssertEqual(service.plugins.count, 1)
        XCTAssertEqual(service.plugins.first?.ui, .vstack([.text("hi")]))
    }

    func testInstallRejectsInvalidUI() {
        let service = PluginsService()
        XCTAssertFalse(service.install(name: "x", version: "1.0.0", track: "wasm", uiJSON: "{bad"))
        XCTAssertTrue(service.plugins.isEmpty)
    }

    func testUpgradeReplacesByName() {
        let service = PluginsService()
        service.install(name: "calc", version: "1.0.0", track: "wasm", uiJSON: ui)
        service.install(name: "calc", version: "2.0.0", track: "wasm", uiJSON: ui)
        XCTAssertEqual(service.plugins.count, 1)
        XCTAssertEqual(service.plugins.first?.version, "2.0.0")
    }

    func testUninstall() {
        let service = PluginsService()
        service.install(name: "calc", version: "1.0.0", track: "wasm", uiJSON: ui)
        service.uninstall(id: "calc@1.0.0")
        XCTAssertTrue(service.plugins.isEmpty)
    }

    func testHandleRecordsEvent() {
        let service = PluginsService()
        service.handle(.buttonClick(action: "run"))
        XCTAssertEqual(service.lastEvent, .buttonClick(action: "run"))
    }

    func testPackageInstallUsesRuntimeAndPersistsPath() throws {
        let runtime = FakePluginRuntime()
        let pathStore = MemoryPluginPackagePathStore()
        let service = PluginsService(
            runtime: runtime,
            packageStore: pathStore,
            allowsExecutablePlugins: true
        )
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-plugin-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: packageURL) }
        try "name = \"calc\"\nversion = \"1.0.0\"".write(
            to: packageURL.appendingPathComponent("plugin.toml"),
            atomically: true,
            encoding: .utf8
        )
        try ui.write(
            to: packageURL.appendingPathComponent("ui.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0, 97, 115, 109]).write(to: packageURL.appendingPathComponent("plugin.wasm"))

        XCTAssertTrue(service.requestInstall(at: packageURL))
        XCTAssertEqual(runtime.installedWasmCount, 0)
        let pending = try XCTUnwrap(service.pendingInstallation)
        XCTAssertEqual(pending.preview.name, "calc")
        service.confirmPendingInstallation(pending)

        XCTAssertEqual(runtime.installedWasmCount, 1)
        XCTAssertEqual(service.plugins.first?.id, "calc@1.0.0")
        XCTAssertEqual(pathStore.paths, [packageURL.path])
    }
}

private final class FakePluginRuntime: PluginRuntimeProviding, @unchecked Sendable {
    private(set) var installedWasmCount = 0
    private var entries: [PluginEntry] = []

    func inspectManifest(_: String) throws -> PluginInstallPreview {
        PluginInstallPreview(
            name: "calc",
            version: "1.0.0",
            networkHosts: [],
            storage: false,
            clipboard: false,
            webview: false,
            webviewBridge: false,
            exposedTools: []
        )
    }

    func installWasm(manifest: String, bytes: Data, uiJSON: String) throws -> PluginEntry {
        installedWasmCount += 1
        let entry = PluginEntry(
            id: "calc@1.0.0",
            name: "calc",
            version: "1.0.0",
            runtime: .wasm,
            uiJson: uiJSON
        )
        entries = [entry]
        return entry
    }

    func installMCP(manifest: String, uiJSON: String) throws -> PluginEntry {
        throw NSError(domain: "test", code: 1)
    }

    func installJS(manifest: String, source: String, uiJSON: String) throws -> PluginEntry {
        let entry = PluginEntry(
            id: "fake-js@1.0.0",
            name: "fake-js",
            version: "1.0.0",
            runtime: .js,
            uiJson: uiJSON
        )
        entries.append(entry)
        return entry
    }

    func list() throws -> [PluginEntry] { entries }

    func uninstall(id: String) throws -> Bool {
        entries.removeAll { $0.id == id }
        return true
    }

    func dispatch(id: String, eventJSON: String) throws -> String { "{}" }
}

private final class MemoryPluginPackagePathStore: PluginPackagePathStoring {
    var paths: [String] = []

    func loadPaths() -> [String] { paths }
    func savePaths(_ paths: [String]) { self.paths = paths }
}
