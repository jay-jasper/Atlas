import CoreGraphics
import XCTest
@testable import Atlas

final class WindowManagementServiceTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    func testLeftHalfUsesVisibleScreenLeftHalf() {
        let frame = WindowFrameCalculator.frame(
            for: .leftHalf,
            currentFrame: .zero,
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    func testRightHalfUsesVisibleScreenRightHalf() {
        let frame = WindowFrameCalculator.frame(
            for: .rightHalf,
            currentFrame: .zero,
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, CGRect(x: 720, y: 0, width: 720, height: 900))
    }

    func testMaximizeUsesVisibleScreenFrame() {
        let frame = WindowFrameCalculator.frame(
            for: .maximize,
            currentFrame: .zero,
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, screen)
    }

    func testCenterKeepsCurrentSizeAndCentersInVisibleScreenFrame() {
        let frame = WindowFrameCalculator.frame(
            for: .center,
            currentFrame: CGRect(x: 0, y: 0, width: 600, height: 400),
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, CGRect(x: 420, y: 250, width: 600, height: 400))
    }

    func testCenterClampsOversizedWindowToVisibleScreenFrame() {
        let frame = WindowFrameCalculator.frame(
            for: .center,
            currentFrame: CGRect(x: 0, y: 0, width: 2_000, height: 1_200),
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, screen)
    }

    func testActionTitlesAreStable() {
        XCTAssertEqual(WindowManagementAction.center.title, "Center Frontmost Window")
        XCTAssertEqual(WindowManagementAction.leftHalf.title, "Move Frontmost Window Left Half")
        XCTAssertEqual(WindowManagementAction.rightHalf.title, "Move Frontmost Window Right Half")
        XCTAssertEqual(WindowManagementAction.maximize.title, "Maximize Frontmost Window")
    }
}
