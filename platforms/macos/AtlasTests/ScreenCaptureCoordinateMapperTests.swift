import XCTest
@testable import Atlas

@MainActor
final class ScreenCaptureCoordinateMapperTests: XCTestCase {
    func testMapsPointRectToPixelRect() {
        let rect = CGRect(x: 10.25, y: 20.5, width: 30.25, height: 40.5)
        let region = ScreenCaptureCoordinateMapper.pixelRegion(fromSelectionRect: rect, backingScaleFactor: 2)
        XCTAssertEqual(region.x, 20)
        XCTAssertEqual(region.y, 41)
        XCTAssertEqual(region.width, 61)
        XCTAssertEqual(region.height, 81)
    }

    func testClampsToAtLeastOnePixel() {
        let rect = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
        let region = ScreenCaptureCoordinateMapper.pixelRegion(fromSelectionRect: rect, backingScaleFactor: 2)
        XCTAssertEqual(region.width, 1)
        XCTAssertEqual(region.height, 1)
    }

    func testCoversFractionalOriginPixelBounds() {
        let rect = CGRect(x: 10.25, y: 20.25, width: 10, height: 10)
        let region = ScreenCaptureCoordinateMapper.pixelRegion(fromSelectionRect: rect, backingScaleFactor: 2)
        XCTAssertEqual(region.x, 20)
        XCTAssertEqual(region.y, 40)
        XCTAssertEqual(region.width, 21)
        XCTAssertEqual(region.height, 21)
    }

    func testStandardizesNegativeSizeRectBeforeMapping() {
        let rect = CGRect(x: 20.25, y: 30.25, width: -10, height: -10)
        let region = ScreenCaptureCoordinateMapper.pixelRegion(fromSelectionRect: rect, backingScaleFactor: 2)
        XCTAssertEqual(region.x, 20)
        XCTAssertEqual(region.y, 40)
        XCTAssertEqual(region.width, 21)
        XCTAssertEqual(region.height, 21)
    }
}
