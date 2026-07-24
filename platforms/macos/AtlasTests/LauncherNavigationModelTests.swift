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

    func testMoveSelectionClampsToAvailableItems() {
        let nav = LauncherNavigationModel()

        nav.moveSelection(by: 1, itemCount: 3)
        XCTAssertEqual(nav.selectedIndex, 1)

        nav.moveSelection(by: 10, itemCount: 3)
        XCTAssertEqual(nav.selectedIndex, 2)

        nav.moveSelection(by: -10, itemCount: 3)
        XCTAssertEqual(nav.selectedIndex, 0)
    }

    func testMoveSelectionResetsWhenThereAreNoItems() {
        let nav = LauncherNavigationModel()
        nav.selectedIndex = 4

        nav.moveSelection(by: 1, itemCount: 0)

        XCTAssertEqual(nav.selectedIndex, 0)
    }
}
