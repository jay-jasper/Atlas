import XCTest
@testable import Atlas

final class DynamicPluginViewTests: XCTestCase {
    func testDecodesEveryNativeContainerAndControl() throws {
        let node = try decode("""
        {
          "kind":"navigation","id":"root","title":"Demo","children":[
            {"kind":"list","id":"list","children":[
              {"kind":"list-item","id":"item","title":"Item","subtitle":"Detail","action":"open"}
            ]},
            {"kind":"form","id":"form","children":[
              {"kind":"text-field","id":"name","placeholder":"Name"},
              {"kind":"toggle","id":"enabled","label":"Enabled","value":true},
              {"kind":"slider","id":"amount","value":2,"min":0,"max":10}
            ]},
            {"kind":"action-panel","id":"actions","children":[
              {"kind":"action","id":"run","title":"Run","action":"run"}
            ]}
          ]
        }
        """)

        XCTAssertEqual(node.kind, .navigation)
        XCTAssertEqual(node.children.map(\.id), ["list", "form", "actions"])
        XCTAssertEqual(node.children[1].children[1].value, .bool(true))
    }

    func testPatchRejectsUnknownNodeWithoutMutatingTree() throws {
        var node = try decode(#"{"kind":"text","id":"root","value":"old"}"#)
        let original = node
        let patch = try JSONDecoder().decode(
            DynamicPluginPatch.self,
            from: Data(#"{"kind":"set-text","id":"missing","value":"new"}"#.utf8)
        )

        XCTAssertThrowsError(try node.apply(patch))
        XCTAssertEqual(node, original)
    }

    func testPatchPreservesStableNodeIdentity() throws {
        var node = try decode("""
        {"kind":"vstack","id":"root","children":[
          {"kind":"text","id":"status","value":"old"},
          {"kind":"text-field","id":"query","placeholder":"Query"}
        ]}
        """)
        let patch = try JSONDecoder().decode(
            DynamicPluginPatch.self,
            from: Data(#"{"kind":"set-text","id":"status","value":"new"}"#.utf8)
        )

        try node.apply(patch)

        XCTAssertEqual(node.children.map(\.id), ["status", "query"])
        XCTAssertEqual(node.children[0].value, .string("new"))
    }

    private func decode(_ json: String) throws -> DynamicPluginNode {
        try JSONDecoder().decode(DynamicPluginNode.self, from: Data(json.utf8))
    }
}
