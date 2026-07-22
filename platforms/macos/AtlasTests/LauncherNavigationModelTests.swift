import XCTest
@testable import Atlas

@MainActor
final class LauncherNavigationModelTests: XCTestCase {
    private func listPage() -> LauncherPage {
        .list(title: "Test", items: { [] })
    }

    func testPushClearsQueryAndSelection() {
        let nav = LauncherNavigationModel()
        nav.query = "abc"
        nav.selectedIndex = 3
        nav.isActionPanelOpen = true

        nav.push(listPage())

        XCTAssertEqual(nav.stack.count, 1)
        XCTAssertEqual(nav.query, "")
        XCTAssertEqual(nav.selectedIndex, 0)
        XCTAssertFalse(nav.isActionPanelOpen)
    }

    func testPopReturnsTrueWhenStackNonEmpty() {
        let nav = LauncherNavigationModel()
        nav.push(listPage())
        XCTAssertTrue(nav.popOrSignalDismiss())
        XCTAssertTrue(nav.stack.isEmpty)
    }

    func testPopClosesActionPanelFirst() {
        let nav = LauncherNavigationModel()
        nav.push(listPage())
        nav.isActionPanelOpen = true

        XCTAssertTrue(nav.popOrSignalDismiss())
        XCTAssertFalse(nav.isActionPanelOpen)
        XCTAssertEqual(nav.stack.count, 1)
    }

    func testPopReturnsFalseAtRoot() {
        let nav = LauncherNavigationModel()
        XCTAssertFalse(nav.popOrSignalDismiss())
    }

    func testResetToRoot() {
        let nav = LauncherNavigationModel()
        nav.push(listPage())
        nav.push(listPage())
        nav.query = "x"
        nav.resetToRoot()
        XCTAssertTrue(nav.stack.isEmpty)
        XCTAssertEqual(nav.query, "")
    }
}
