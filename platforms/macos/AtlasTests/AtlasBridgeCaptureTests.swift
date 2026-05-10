import AppKit
import XCTest
@testable import Atlas

final class AtlasBridgeCaptureTests: XCTestCase {
    func testMockCaptureRegionReturnsPngData() {
        let data = AtlasBridge.captureRegion(x: 0, y: 0, width: 120, height: 80)

        XCTAssertNotNil(data)
        XCTAssertEqual(Array(data!.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testMockCaptureRegionReturnsDeterministicBytes() {
        let firstCapture = AtlasBridge.captureRegion(x: 10, y: 20, width: 120, height: 80)
        let secondCapture = AtlasBridge.captureRegion(x: 10, y: 20, width: 120, height: 80)

        XCTAssertEqual(firstCapture, secondCapture)
    }

    func testMockCaptureRegionReturnsDecodableImageWithExpectedSize() throws {
        let data = try XCTUnwrap(AtlasBridge.captureRegion(x: 0, y: 0, width: 120, height: 80))
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertEqual(image.pixelsWide, 120)
        XCTAssertEqual(image.pixelsHigh, 80)
    }

    func testMockCaptureFullScreenReturnsDecodableImageWithExpectedSize() throws {
        let data = try XCTUnwrap(AtlasBridge.captureFullScreen())
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertEqual(image.pixelsWide, 1440)
        XCTAssertEqual(image.pixelsHigh, 900)
    }
}
