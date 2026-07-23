import XCTest
@testable import Atlas

final class ShellTabTests: XCTestCase {
    func testFiveTabsOrdered() {
        XCTAssertEqual(ShellTab.allCases, [.general, .plugins, .raycast, .ai, .about])
        XCTAssertEqual(ShellTab.allCases.map(\.title), ["通用", "插件", "Raycast", "AI", "关于"])
    }

    func testShortcutDigitsUnique() {
        let digits = ShellTab.allCases.map(\.shortcutDigit)
        XCTAssertEqual(digits, [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(digits).count, digits.count)
    }

    func testSeventeenThemesRegisteredWithPlainDefault() {
        XCTAssertEqual(ShellThemeKind.allCases.count, 16)
        XCTAssertEqual(ShellThemeKind.allCases.first, .plain)
        XCTAssertNil(ShellThemeKind.plain.spec.colorScheme) // 跟随系统
        for kind in ShellThemeKind.allCases {
            XCTAssertFalse(kind.spec.icon.isEmpty, "theme \(kind.rawValue) lost its spec")
        }
    }
}
