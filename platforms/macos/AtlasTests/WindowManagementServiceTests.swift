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

    func testConvertsAXFrameToAppKitFrameUsingScreenCoordinateSpace() {
        let frame = WindowCoordinateConverter.appKitFrame(
            fromAXFrame: CGRect(x: 100, y: 100, width: 400, height: 300),
            inScreenFrame: screen
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 500, width: 400, height: 300))
    }

    func testConvertsAppKitFrameToAXFrameUsingScreenCoordinateSpace() {
        let frame = WindowCoordinateConverter.axFrame(
            fromAppKitFrame: CGRect(x: 100, y: 500, width: 400, height: 300),
            inScreenFrame: screen
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 100, width: 400, height: 300))
    }

    func testCoordinateConversionRoundTripsWithNonZeroScreenOrigin() {
        let screen = CGRect(x: 200, y: 50, width: 1_440, height: 900)
        let axFrame = CGRect(x: 300, y: 150, width: 400, height: 300)

        let appKitFrame = WindowCoordinateConverter.appKitFrame(
            fromAXFrame: axFrame,
            inScreenFrame: screen
        )
        let convertedAXFrame = WindowCoordinateConverter.axFrame(
            fromAppKitFrame: appKitFrame,
            inScreenFrame: screen
        )

        XCTAssertEqual(appKitFrame, CGRect(x: 300, y: 550, width: 400, height: 300))
        XCTAssertEqual(convertedAXFrame, axFrame)
    }

    func testGridTopLeftUsesOneThirdOfVisibleScreen() {
        let frame = WindowFrameCalculator.frame(
            for: .grid(WindowGridPosition(row: 0, column: 0)),
            currentFrame: .zero,
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 600, width: 480, height: 300))
    }

    func testGridCenterUsesMiddleCell() {
        let frame = WindowFrameCalculator.frame(
            for: .grid(WindowGridPosition(row: 1, column: 1)),
            currentFrame: .zero,
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, CGRect(x: 480, y: 300, width: 480, height: 300))
    }

    func testGridBottomRightUsesDisplayOriginAndIntegralFrame() {
        let frame = WindowFrameCalculator.frame(
            for: .grid(WindowGridPosition(row: 2, column: 2)),
            currentFrame: .zero,
            visibleScreenFrame: CGRect(x: 200, y: 50, width: 1_440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 1_160, y: 50, width: 480, height: 300))
    }

    func testGridPositionClampsInvalidInputToGridBounds() {
        XCTAssertEqual(WindowGridPosition(row: -1, column: 9), WindowGridPosition(row: 0, column: 2))
    }

    func testActionTitlesAreStable() {
        XCTAssertEqual(WindowManagementAction.center.title, "Center Frontmost Window")
        XCTAssertEqual(WindowManagementAction.leftHalf.title, "Move Frontmost Window Left Half")
        XCTAssertEqual(WindowManagementAction.rightHalf.title, "Move Frontmost Window Right Half")
        XCTAssertEqual(WindowManagementAction.maximize.title, "Maximize Frontmost Window")
        XCTAssertEqual(
            WindowManagementAction.grid(WindowGridPosition(row: 0, column: 0)).title,
            "Move Frontmost Window Top Left"
        )
    }
}
