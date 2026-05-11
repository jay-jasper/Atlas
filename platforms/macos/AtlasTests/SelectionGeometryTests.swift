import XCTest
@testable import Atlas

final class SelectionGeometryTests: XCTestCase {
    func testNormalizedRectStandardizesAndIntegralizes() {
        let rect = SelectionGeometry.normalizedRect(
            from: CGPoint(x: 20.2, y: 30.8),
            to: CGPoint(x: 5.7, y: 10.1)
        )

        XCTAssertEqual(rect, CGRect(x: 5, y: 10, width: 15, height: 21))
    }

    func testClampPointKeepsPointInsideBounds() {
        let point = SelectionGeometry.clamp(
            CGPoint(x: -5, y: 120),
            bounds: CGSize(width: 100, height: 80)
        )

        XCTAssertEqual(point, CGPoint(x: 0, y: 80))
    }

    func testClampRectKeepsRectInsideBounds() {
        let rect = SelectionGeometry.clamp(
            CGRect(x: 90, y: -10, width: 30, height: 20),
            bounds: CGSize(width: 100, height: 80)
        )

        XCTAssertEqual(rect, CGRect(x: 70, y: 0, width: 30, height: 20))
    }

    func testMoveOffsetsAndClampsRect() {
        let rect = SelectionGeometry.move(
            CGRect(x: 10, y: 10, width: 30, height: 20),
            by: CGSize(width: 80, height: 70),
            bounds: CGSize(width: 100, height: 80)
        )

        XCTAssertEqual(rect, CGRect(x: 70, y: 60, width: 30, height: 20))
    }

    func testMoveWithFractionalDeltaPreservesSelectionSize() {
        let rect = SelectionGeometry.move(
            CGRect(x: 10, y: 10, width: 30, height: 20),
            by: CGSize(width: 0.25, height: 0.25),
            bounds: CGSize(width: 100, height: 80)
        )

        XCTAssertEqual(rect.size, CGSize(width: 30, height: 20))
        XCTAssertEqual(rect.origin, CGPoint(x: 10, y: 10))
    }

    func testNudgeUsesOnePixelOrTenPixels() {
        XCTAssertEqual(SelectionGeometry.nudgeDelta(.left, isLargeStep: false), CGSize(width: -1, height: 0))
        XCTAssertEqual(SelectionGeometry.nudgeDelta(.right, isLargeStep: true), CGSize(width: 10, height: 0))
        XCTAssertEqual(SelectionGeometry.nudgeDelta(.up, isLargeStep: false), CGSize(width: 0, height: -1))
        XCTAssertEqual(SelectionGeometry.nudgeDelta(.down, isLargeStep: true), CGSize(width: 0, height: 10))
    }

    func testSizeLabelUsesIntegralDimensions() {
        XCTAssertEqual(
            SelectionGeometry.sizeLabel(for: CGRect(x: 0, y: 0, width: 99.6, height: 40.2)),
            "100 x 40"
        )
    }
}
