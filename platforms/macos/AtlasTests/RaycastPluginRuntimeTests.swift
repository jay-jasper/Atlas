import XCTest
@testable import Atlas

final class RaycastPluginRuntimeTests: XCTestCase {
    func testRaycastListSchemaAndActionRoundTrip() throws {
        let data = Data("""
        {
          "kind": "list",
          "id": "root",
          "children": [{
            "kind": "list-item",
            "id": "one",
            "title": "One",
            "action": "copy"
          }]
        }
        """.utf8)
        let root = try JSONDecoder().decode(DynamicPluginNode.self, from: data)
        XCTAssertEqual(root.kind, .list)
        XCTAssertEqual(root.children.first?.action, "copy")
        XCTAssertEqual(
            DynamicPluginUIEvent.action(id: "one", action: "copy").json,
            #"{"action":"copy","id":"one","kind":"action-invoked"}"#
        )
    }

    func testFormAndNavigationPatchesPreserveStableIDs() throws {
        var root = try JSONDecoder().decode(
            DynamicPluginNode.self,
            from: Data(#"{"kind":"form","id":"form","children":[{"kind":"text-field","id":"query","placeholder":"Search"}]}"#.utf8)
        )
        let patch = try JSONDecoder().decode(
            DynamicPluginPatch.self,
            from: Data(#"{"kind":"set-value","id":"query","value":"Atlas"}"#.utf8)
        )
        try root.apply(patch)
        XCTAssertEqual(root.children.first?.id, "query")
        XCTAssertEqual(root.children.first?.value, .string("Atlas"))
    }
}
