import XCTest
@testable import Atlas

final class ShellTabTests: XCTestCase {
    func testFiveTabsOrdered() {
        XCTAssertEqual(ShellTab.allCases, [.general, .plugins, .ai, .settings, .about])
        XCTAssertEqual(ShellTab.allCases.map(\.title), ["通用", "插件", "AI", "设置", "关于"])
    }

    func testShortcutDigitsUnique() {
        let digits = ShellTab.allCases.map(\.shortcutDigit)
        XCTAssertEqual(digits, [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(digits).count, digits.count)
    }

    func testAllSixteenThemesStillRegistered() {
        XCTAssertEqual(ShellThemeKind.allCases.count, 16)
        // Spot-check the registry keeps resolving specs for every theme.
        for kind in ShellThemeKind.allCases {
            XCTAssertFalse(kind.spec.icon.isEmpty, "theme \(kind.rawValue) lost its spec")
        }
    }
}
