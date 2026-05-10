import AppKit
import XCTest
@testable import Atlas

final class AtlasBridgeCaptureTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.captureService = .live
        super.tearDown()
    }

    func testBridgeRegionUsesCaptureService() throws {
        AtlasBridge.captureService = AtlasCaptureService(
            captureFullScreen: { Data([9]) },
            captureRegion: { x, y, width, height in
                XCTAssertEqual(x, 1)
                XCTAssertEqual(y, 2)
                XCTAssertEqual(width, 3)
                XCTAssertEqual(height, 4)
                return Data([1, 2, 3])
            }
        )
        let data = try AtlasBridge.captureRegion(x: 1, y: 2, width: 3, height: 4)
        XCTAssertEqual(data, Data([1, 2, 3]))
    }

    func testBridgeFullScreenUsesCaptureService() throws {
        AtlasBridge.captureService = AtlasCaptureService(
            captureFullScreen: { Data([7, 8]) },
            captureRegion: { _, _, _, _ in Data() }
        )
        let data = try AtlasBridge.captureFullScreen()
        XCTAssertEqual(data, Data([7, 8]))
    }
}
