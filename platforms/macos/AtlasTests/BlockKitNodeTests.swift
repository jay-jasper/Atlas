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
}
