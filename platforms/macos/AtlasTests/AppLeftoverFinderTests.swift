import XCTest
@testable import Atlas

@MainActor
final class AppLeftoverFinderTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")

    func testCandidatePathsIncludeBundleAndName() {
        let paths = AppLeftoverFinder.candidatePaths(home: home, appName: "Acme", bundleID: "com.acme.app")
            .map { $0.url.path }
        XCTAssertTrue(paths.contains("/Users/test/Library/Application Support/com.acme.app"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Caches/com.acme.app"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Preferences/com.acme.app.plist"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Containers/com.acme.app"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Application Support/Acme"))
    }

    func testNoBundleIDStillUsesName() {
        let paths = AppLeftoverFinder.candidatePaths(home: home, appName: "Acme", bundleID: nil).map { $0.url.path }
        XCTAssertFalse(paths.isEmpty)
        XCTAssertTrue(paths.allSatisfy { $0.contains("Acme") })
    }

    func testFindReturnsExistingPathsSortedBySize() {
        // Prober reports two paths existing with different sizes.
        let existing: [String: Int64] = [
            "/Users/test/Library/Caches/com.acme.app": 5000,
            "/Users/test/Library/Application Support/com.acme.app": 200,
        ]
        let leftovers = AppLeftoverFinder.find(home: home, appName: "Acme", bundleID: "com.acme.app") { url in
            existing[url.path]
        }
        XCTAssertEqual(leftovers.count, 2)
        XCTAssertEqual(leftovers.first?.size, 5000) // sorted descending
        XCTAssertEqual(leftovers.first?.category, "Caches")
    }

    func testFindDeduplicatesPaths() {
        // Same name and bundle would not produce duplicate Application Support entries
        // for identical paths; ensure unique paths only.
        let leftovers = AppLeftoverFinder.find(home: home, appName: "X", bundleID: "X") { _ in 10 }
        let paths = leftovers.map(\.path)
        XCTAssertEqual(Set(paths).count, paths.count)
    }
}
