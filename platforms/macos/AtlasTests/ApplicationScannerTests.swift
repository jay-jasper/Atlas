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

        let scanner = FileSystemApplicationScanner(directories: [root], extraAppPaths: [])

        XCTAssertEqual(scanner.scanApplications().map { AppEntry(name: $0.name, url: $0.url) }, [
            AppEntry(name: "Safari", url: appURL),
        ])
    }

    func testScannerDeduplicatesByURL() throws {
        let appURL = try makeDirectory("Xcode.app")
        let scanner = FileSystemApplicationScanner(directories: [root, root], extraAppPaths: [])

        XCTAssertEqual(scanner.scanApplications().map { AppEntry(name: $0.name, url: $0.url) }, [
            AppEntry(name: "Xcode", url: appURL),
        ])
    }

    func testScannerSortsByName() throws {
        let zedURL = try makeDirectory("Zed.app")
        let arcURL = try makeDirectory("Arc.app")
        let xcodeURL = try makeDirectory("Xcode.app")

        let scanner = FileSystemApplicationScanner(directories: [root], extraAppPaths: [])

        XCTAssertEqual(scanner.scanApplications().map { AppEntry(name: $0.name, url: $0.url) }, [
            AppEntry(name: "Arc", url: arcURL),
            AppEntry(name: "Xcode", url: xcodeURL),
            AppEntry(name: "Zed", url: zedURL),
        ])
    }

    func testScannerSkipsMissingDirectories() throws {
        let existingURL = try makeDirectory("Terminal.app")
        let missing = root.appendingPathComponent("Missing", isDirectory: true)
        let scanner = FileSystemApplicationScanner(directories: [missing, root], extraAppPaths: [])

        XCTAssertEqual(scanner.scanApplications().map { AppEntry(name: $0.name, url: $0.url) }, [
            AppEntry(name: "Terminal", url: existingURL),
        ])
    }

    func testDefaultDirectoriesIncludeUserApplications() {
        let userApplications = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Applications"))

        XCTAssertTrue(FileSystemApplicationScanner.defaultDirectories.contains(userApplications))
    }

    func testScannerUsesSpotlightLocalizedDisplayName() throws {
        let appURL = try makeDirectory("System Information.app")
        let scanner = FileSystemApplicationScanner(
            directories: [root],
            extraAppPaths: [],
            metadataDisplayName: { url in
                url == appURL ? "系统信息.app" : nil
            }
        )

        XCTAssertEqual(scanner.scanApplications().first?.displayName, "系统信息")
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
