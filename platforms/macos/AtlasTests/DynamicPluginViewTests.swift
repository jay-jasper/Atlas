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

    func testDecodesScopedPersistentWebView() throws {
        let node = try decode("""
        {
          "kind":"web-view",
          "id":"assistant",
          "url":"https://chatgpt.com/",
          "allowed_hosts":["chatgpt.com","openai.com"],
          "profile":"chatgpt",
          "persistent":true
        }
        """)

        XCTAssertEqual(node.kind, .webView)
        XCTAssertEqual(node.allowedHosts, ["chatgpt.com", "openai.com"])
        XCTAssertEqual(node.profile, "chatgpt")
        XCTAssertTrue(node.persistent)
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

    func testWebNavigationPolicyRestrictsTopLevelNavigationToAllowedHosts() throws {
        let allowedHosts: Set<String> = ["chatgpt.com", "openai.com"]

        XCTAssertTrue(PluginWebNavigationPolicy.permits(
            try XCTUnwrap(URL(string: "https://chatgpt.com/")),
            allowedHosts: allowedHosts,
            isMainFrame: true
        ))
        XCTAssertTrue(PluginWebNavigationPolicy.permits(
            try XCTUnwrap(URL(string: "https://auth.openai.com/")),
            allowedHosts: allowedHosts,
            isMainFrame: true
        ))
        XCTAssertFalse(PluginWebNavigationPolicy.permits(
            try XCTUnwrap(URL(string: "https://example.com/")),
            allowedHosts: allowedHosts,
            isMainFrame: true
        ))
        XCTAssertFalse(PluginWebNavigationPolicy.permits(
            try XCTUnwrap(URL(string: "data:text/html,blocked")),
            allowedHosts: allowedHosts,
            isMainFrame: true
        ))
    }

    func testWebNavigationPolicyAllowsSafeProviderSubframes() throws {
        let allowedHosts: Set<String> = ["chatgpt.com"]

        for rawURL in [
            "https://challenges.cloudflare.com/widget",
            "about:srcdoc",
            "blob:https://chatgpt.com/8f7a5c6f",
            "data:text/html,embedded"
        ] {
            XCTAssertTrue(PluginWebNavigationPolicy.permits(
                try XCTUnwrap(URL(string: rawURL)),
                allowedHosts: allowedHosts,
                isMainFrame: false
            ), rawURL)
        }
        XCTAssertFalse(PluginWebNavigationPolicy.permits(
            try XCTUnwrap(URL(string: "file:///tmp/private")),
            allowedHosts: allowedHosts,
            isMainFrame: false
        ))
    }

    private func decode(_ json: String) throws -> DynamicPluginNode {
        try JSONDecoder().decode(DynamicPluginNode.self, from: Data(json.utf8))
    }
}
