import XCTest
@testable import Atlas

@MainActor
final class ApplicationScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = scannerVisibleTemporaryDirectory()
            .appendingPathComponent("ApplicationScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
        try super.tearDownWithError()
    }

    func testScannerReturnsOnlyAppBundles() throws {
        let appURL = try makeDirectory("Safari.app")
        _ = try makeDirectory("NotAnApp")
        try "text".write(to: root.appendingPathComponent("Notes.txt"), atomically: true, encoding: .utf8)

        let scanner = FileSystemApplicationScanner(directories: [root])

        XCTAssertEqual(scanner.scanApplications(), [
            AppEntry(name: "Safari", url: appURL),
        ])
    }

    func testScannerDeduplicatesByURL() throws {
        let appURL = try makeDirectory("Xcode.app")
        let scanner = FileSystemApplicationScanner(directories: [root, root])

        XCTAssertEqual(scanner.scanApplications(), [
            AppEntry(name: "Xcode", url: appURL),
        ])
    }

    func testScannerSortsByName() throws {
        let zedURL = try makeDirectory("Zed.app")
        let arcURL = try makeDirectory("Arc.app")
        let xcodeURL = try makeDirectory("Xcode.app")

        let scanner = FileSystemApplicationScanner(directories: [root])

        XCTAssertEqual(scanner.scanApplications(), [
            AppEntry(name: "Arc", url: arcURL),
            AppEntry(name: "Xcode", url: xcodeURL),
            AppEntry(name: "Zed", url: zedURL),
        ])
    }

    func testScannerSkipsMissingDirectories() throws {
        let existingURL = try makeDirectory("Terminal.app")
        let missing = root.appendingPathComponent("Missing", isDirectory: true)
        let scanner = FileSystemApplicationScanner(directories: [missing, root])

        XCTAssertEqual(scanner.scanApplications(), [
            AppEntry(name: "Terminal", url: existingURL),
        ])
    }

    func testDefaultDirectoriesIncludeUserApplications() {
        let userApplications = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Applications"))

        XCTAssertTrue(FileSystemApplicationScanner.defaultDirectories.contains(userApplications))
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func scannerVisibleTemporaryDirectory() -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        if temporaryDirectory.path.hasPrefix("/var/") {
            return URL(fileURLWithPath: "/private" + temporaryDirectory.path, isDirectory: true)
        }
        return temporaryDirectory
    }
}
