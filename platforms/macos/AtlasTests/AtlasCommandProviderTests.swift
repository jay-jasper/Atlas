import XCTest
@testable import Atlas

@MainActor
final class AtlasCommandProviderTests: XCTestCase {
    private var provider: AtlasCommandProvider!

    override func setUp() {
        provider = AtlasCommandProvider(
            onCaptureDesktop: {},
            onCaptureArea: {},
            onCaptureWindow: {},
            onOpenSettings: {}
        )
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    func testEmptyQueryReturnsAllDefaultCommands() {
        let results = provider.results(for: "")
        XCTAssertFalse(results.isEmpty)
        // All core commands present
        XCTAssertTrue(results.contains { $0.title == "Capture Desktop" })
        XCTAssertTrue(results.contains { $0.title == "Capture Area" })
        XCTAssertTrue(results.contains { $0.title == "Capture Window" })
        XCTAssertTrue(results.contains { $0.title == "Screenshot Library" })
        XCTAssertTrue(results.contains { $0.title == "Port Lookup" })
        XCTAssertTrue(results.contains { $0.title == "Open Settings" })
    }

    func testTitlePrefixMatchReturnsResult() {
        let results = provider.results(for: "capture")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy {
            $0.title.lowercased().hasPrefix("capture") ||
            $0.keywords.contains { $0.localizedCaseInsensitiveContains("capture") }
        })
    }

    func testKeywordSubstringMatchReturnsResult() {
        let results = provider.results(for: "port")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.title == "Port Lookup" })
    }

    func testCaseInsensitiveMatching() {
        let lower = provider.results(for: "screenshot")
        let upper = provider.results(for: "SCREENSHOT")
        XCTAssertEqual(lower.map(\.title).sorted(), upper.map(\.title).sorted())
    }

    func testNonMatchingQueryReturnsEmpty() {
        let results = provider.results(for: "xyzzy123")
        XCTAssertTrue(results.isEmpty)
    }

    func testAllCommandsHaveAtlasCategory() {
        let results = provider.results(for: "")
        XCTAssertTrue(results.allSatisfy { $0.category == "Atlas" })
    }

    func testCaptureWindowActionIsPush() {
        let results = provider.results(for: "Capture Window")
        let cmd = results.first { $0.title == "Capture Window" }!
        if case .push(let dest) = cmd.action {
            XCTAssertEqual(dest, .windowPicker)
        } else {
            XCTFail("expected .push(.windowPicker)")
        }
    }

    func testScreenshotLibraryActionIsPush() {
        let cmd = provider.results(for: "").first { $0.title == "Screenshot Library" }!
        if case .push(let dest) = cmd.action {
            XCTAssertEqual(dest, .screenshotLibrary)
        } else {
            XCTFail("expected .push(.screenshotLibrary)")
        }
    }

    func testPortLookupActionIsPush() {
        let cmd = provider.results(for: "").first { $0.title == "Port Lookup" }!
        if case .push(let dest) = cmd.action {
            XCTAssertEqual(dest, .portLookup)
        } else {
            XCTFail("expected .push(.portLookup)")
        }
    }

    func testCaptureDesktopCallsCallback() {
        var called = false
        let p = AtlasCommandProvider(
            onCaptureDesktop: { called = true },
            onCaptureArea: {},
            onCaptureWindow: {},
            onOpenSettings: {}
        )
        let cmd = p.results(for: "").first { $0.title == "Capture Desktop" }!
        if case .execute(let fn) = cmd.action { fn() }
        XCTAssertTrue(called)
    }
}
