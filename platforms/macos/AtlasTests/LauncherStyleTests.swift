import XCTest
@testable import Atlas

@MainActor
final class LauncherStyleTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "LauncherStyleTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testCodableRoundTripAllBackgrounds() throws {
        let backgrounds: [LauncherStyle.Background] = [
            .theme,
            .material(opacity: 0.7),
            .solid(RGBAColor(r: 0.1, g: 0.2, b: 0.3, a: 1)),
            .gradient(.white, RGBAColor(r: 0, g: 0, b: 1, a: 1), angleDegrees: 45),
            .builtinPattern("paper"),
            .imageFile("/tmp/bg.png"),
        ]
        for background in backgrounds {
            var style = LauncherStyle.default
            style.background = background
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(LauncherStyle.self, from: data)
            XCTAssertEqual(decoded, style)
        }
    }

    func testDecodeGarbageFallsBackToDefault() {
        defaults.set(Data("junk".utf8), forKey: "launcher.style")
        let store = LauncherStyleStore(defaults: defaults)
        XCTAssertEqual(store.style, .default)
        XCTAssertEqual(store.style.maxVisibleRows, 10)
    }

    func testStorePersistsAcrossInstances() {
        let store = LauncherStyleStore(defaults: defaults)
        store.style.cornerRadius = 24
        store.style.panelWidth = 720

        let reloaded = LauncherStyleStore(defaults: defaults)
        XCTAssertEqual(reloaded.style.cornerRadius, 24)
        XCTAssertEqual(reloaded.style.panelWidth, 720)
    }

    func testResetRestoresDefault() {
        let store = LauncherStyleStore(defaults: defaults)
        store.style.fontSize = 19
        store.reset()
        XCTAssertEqual(store.style, .default)
        XCTAssertEqual(store.style.maxVisibleRows, 10)

        let reloaded = LauncherStyleStore(defaults: defaults)
        XCTAssertEqual(reloaded.style, .default)
    }

    func testStoreMigratesOldDefaultVisibleRowsToTen() throws {
        var legacyStyle = LauncherStyle.default
        legacyStyle.maxVisibleRows = 8
        defaults.set(try JSONEncoder().encode(legacyStyle), forKey: "launcher.style")

        let store = LauncherStyleStore(defaults: defaults)

        XCTAssertEqual(store.style.maxVisibleRows, 10)
    }

    func testSanitizedClampsOutOfRangeValues() {
        var style = LauncherStyle.default
        style.panelWidth = 5000
        style.maxVisibleRows = 1
        style.cornerRadius = -3
        let sane = style.sanitized()
        XCTAssertEqual(sane.panelWidth, 960)
        XCTAssertEqual(sane.maxVisibleRows, 4)
        XCTAssertEqual(sane.cornerRadius, 0)
    }
}
