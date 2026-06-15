import XCTest
@testable import Atlas

@MainActor
final class BrowserRouterTests: XCTestCase {
    private let rules = [
        BrowserRoute(pattern: "*.slack.com", browserBundleID: "com.apple.Safari", browserName: "Safari"),
        BrowserRoute(pattern: "github.com", browserBundleID: "com.google.Chrome", browserName: "Chrome"),
        BrowserRoute(pattern: "*figma*", browserBundleID: "company.thebrowser.Browser", browserName: "Arc"),
    ]

    func testWildcardSubdomain() {
        XCTAssertEqual(
            BrowserRouter.resolve(url: "https://app.slack.com/client", rules: rules, defaultBrowserBundleID: "def"),
            "com.apple.Safari"
        )
    }

    func testBareDomain() {
        XCTAssertEqual(
            BrowserRouter.resolve(url: "https://github.com/anthropics", rules: rules, defaultBrowserBundleID: "def"),
            "com.google.Chrome"
        )
        // subdomain of a bare-domain rule still matches
        XCTAssertEqual(
            BrowserRouter.resolve(url: "https://gist.github.com/x", rules: rules, defaultBrowserBundleID: "def"),
            "com.google.Chrome"
        )
    }

    func testSubstringGlob() {
        XCTAssertEqual(
            BrowserRouter.resolve(url: "https://www.figma.com/file/abc", rules: rules, defaultBrowserBundleID: "def"),
            "company.thebrowser.Browser"
        )
    }

    func testFallsBackToDefault() {
        XCTAssertEqual(
            BrowserRouter.resolve(url: "https://example.com", rules: rules, defaultBrowserBundleID: "def"),
            "def"
        )
    }

    func testFirstMatchWins() {
        let ordered = [
            BrowserRoute(pattern: "github.com", browserBundleID: "first", browserName: "First"),
            BrowserRoute(pattern: "*.com", browserBundleID: "second", browserName: "Second"),
        ]
        XCTAssertEqual(
            BrowserRouter.resolve(url: "https://github.com", rules: ordered, defaultBrowserBundleID: "def"),
            "first"
        )
    }

    func testGlobMatchAnchoring() {
        XCTAssertTrue(BrowserRouter.globMatch(pattern: "https://*.slack.com*", text: "https://app.slack.com/x"))
        XCTAssertFalse(BrowserRouter.globMatch(pattern: "https://slack.com", text: "https://notslack.com"))
    }
}

@MainActor
final class BrowserRouterServiceTests: XCTestCase {
    private let browsers = [
        InstalledBrowser(bundleID: "com.apple.Safari", name: "Safari"),
        InstalledBrowser(bundleID: "com.google.Chrome", name: "Chrome"),
    ]

    func testAddDeleteAndResolve() {
        let service = BrowserRouterService(
            store: InMemoryBrowserRouteStore(),
            installedBrowsers: browsers,
            defaultBrowserBundleID: "com.apple.Safari"
        )
        service.addRoute(pattern: "github.com", browser: browsers[1])
        XCTAssertEqual(service.routes.count, 1)
        XCTAssertEqual(service.resolve("https://github.com/x"), "com.google.Chrome")

        service.delete(id: service.routes[0].id)
        XCTAssertEqual(service.resolve("https://github.com/x"), "com.apple.Safari")
    }

    func testRunTestProducesReadableResult() {
        let service = BrowserRouterService(
            store: InMemoryBrowserRouteStore(),
            installedBrowsers: browsers,
            defaultBrowserBundleID: "com.apple.Safari"
        )
        service.addRoute(pattern: "github.com", browser: browsers[1])
        service.testURL = "https://github.com"
        service.runTest()
        XCTAssertEqual(service.testResult, "Opens in: Chrome")
    }
}
