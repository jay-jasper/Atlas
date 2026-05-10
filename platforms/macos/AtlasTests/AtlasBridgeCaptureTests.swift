import XCTest
@testable import Atlas

final class AtlasBridgeCaptureTests: XCTestCase {
    func testMockCaptureRegionReturnsPngData() {
        let data = AtlasBridge.captureRegion(x: 0, y: 0, width: 120, height: 80)

        XCTAssertNotNil(data)
        XCTAssertEqual(Array(data!.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
