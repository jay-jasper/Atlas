import XCTest
@testable import Atlas

@MainActor
final class NotchGeometryTests: XCTestCase {
    func testHasNotch() {
        XCTAssertTrue(NotchGeometry.hasNotch(topSafeAreaInset: 32))
        XCTAssertFalse(NotchGeometry.hasNotch(topSafeAreaInset: 0))
    }

    func testOverlayFrameCentersAtTop() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NotchGeometry.overlayFrame(screenFrame: screen, size: CGSize(width: 200, height: 32))
        XCTAssertEqual(frame.midX, 720, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 900, accuracy: 0.001) // pinned to top
        XCTAssertEqual(frame.width, 200)
    }

    func testOverlayFrameRespectsScreenOrigin() {
        let screen = CGRect(x: 1440, y: 0, width: 1440, height: 900) // second display
        let frame = NotchGeometry.overlayFrame(screenFrame: screen, size: CGSize(width: 100, height: 30))
        XCTAssertEqual(frame.midX, 1440 + 720, accuracy: 0.001)
    }

    func testEstimatedNotchWidthClamps() {
        XCTAssertEqual(NotchGeometry.estimatedNotchWidth(menuBarHeight: 24), 150, accuracy: 0.001) // 120 -> clamped up
        XCTAssertEqual(NotchGeometry.estimatedNotchWidth(menuBarHeight: 100), 230, accuracy: 0.001) // clamped down
    }

    func testExpandedWidthBoundedByScreen() {
        XCTAssertEqual(NotchGeometry.expandedWidth(screenWidth: 1440), 360, accuracy: 0.001)
        XCTAssertEqual(NotchGeometry.expandedWidth(screenWidth: 400), 320, accuracy: 0.001) // 400 - 80
    }

    func testServiceToggleExpanded() {
        let service = NotchService()
        XCTAssertFalse(service.isExpanded)
        service.toggleExpanded()
        XCTAssertTrue(service.isExpanded)
    }
}
