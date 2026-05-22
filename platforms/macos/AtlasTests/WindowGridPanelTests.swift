import XCTest
@testable import Atlas

@MainActor
final class WindowGridPanelTests: XCTestCase {
    func testGridPositionsAreStableTopToBottomLeftToRight() {
        XCTAssertEqual(WindowGridPanel.gridPositions, [
            WindowGridPosition(row: 0, column: 0),
            WindowGridPosition(row: 0, column: 1),
            WindowGridPosition(row: 0, column: 2),
            WindowGridPosition(row: 1, column: 0),
            WindowGridPosition(row: 1, column: 1),
            WindowGridPosition(row: 1, column: 2),
            WindowGridPosition(row: 2, column: 0),
            WindowGridPosition(row: 2, column: 1),
            WindowGridPosition(row: 2, column: 2),
        ])
    }

    func testSelectingGridCellPerformsGridActionWhenEnabledAndTrusted() {
        let manager = FakeWindowGridManager()
        let permission = FakeWindowManagementPermissionChecker(isTrusted: true)
        let model = WindowGridPanelModel(
            windowManager: manager,
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        let result = model.select(position: WindowGridPosition(row: 2, column: 1))

        XCTAssertEqual(result, .performed)
        XCTAssertEqual(manager.performedActions, [.grid(WindowGridPosition(row: 2, column: 1))])
        XCTAssertEqual(permission.requestCount, 0)
    }

    func testSelectingGridCellDoesNothingWhenFeatureDisabled() {
        let manager = FakeWindowGridManager()
        let permission = FakeWindowManagementPermissionChecker(isTrusted: true)
        let model = WindowGridPanelModel(
            windowManager: manager,
            permissionChecker: permission,
            isFeatureEnabled: { false }
        )

        let result = model.select(position: WindowGridPosition(row: 0, column: 0))

        XCTAssertEqual(result, .featureDisabled)
        XCTAssertTrue(manager.performedActions.isEmpty)
    }

    func testSelectingGridCellRequestsAccessibilityWhenNotTrusted() {
        let manager = FakeWindowGridManager()
        let permission = FakeWindowManagementPermissionChecker(isTrusted: false)
        let model = WindowGridPanelModel(
            windowManager: manager,
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        let result = model.select(position: WindowGridPosition(row: 1, column: 1))

        XCTAssertEqual(result, .permissionRequired)
        XCTAssertTrue(manager.performedActions.isEmpty)
        XCTAssertEqual(permission.requestCount, 1)
    }

    func testRequestPermissionRefreshesAccessibilityStatus() {
        let permission = FakeWindowManagementPermissionChecker(isTrusted: false)
        permission.trustAfterRequest = true
        let model = WindowGridPanelModel(
            windowManager: FakeWindowGridManager(),
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        XCTAssertEqual(model.accessibilityStatusText, "Accessibility access required")

        model.requestPermission()

        XCTAssertEqual(model.accessibilityStatusText, "Accessibility access enabled")
        XCTAssertEqual(permission.requestCount, 1)
    }
}

private final class FakeWindowGridManager: WindowManaging {
    private(set) var performedActions: [WindowManagementAction] = []

    @discardableResult
    func perform(_ action: WindowManagementAction) -> Bool {
        performedActions.append(action)
        return true
    }
}

private final class FakeWindowManagementPermissionChecker: WindowManagementPermissionChecking {
    var isTrusted: Bool
    var trustAfterRequest = false
    private(set) var requestCount = 0

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func requestPermission() {
        requestCount += 1
        if trustAfterRequest {
            isTrusted = true
        }
    }
}
