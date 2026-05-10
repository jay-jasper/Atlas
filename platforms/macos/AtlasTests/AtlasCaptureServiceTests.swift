import XCTest
@testable import Atlas

final class AtlasCaptureServiceTests: XCTestCase {
    func testCaptureRegionUsesInjectedFunction() throws {
        let expected = Data([1, 2, 3])
        let service = AtlasCaptureService(
            captureFullScreen: { Data([9]) },
            captureRegion: { x, y, width, height in
                XCTAssertEqual(x, 10)
                XCTAssertEqual(y, 20)
                XCTAssertEqual(width, 30)
                XCTAssertEqual(height, 40)
                return expected
            }
        )

        let data = try service.captureRegion(.init(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(data, expected)
    }

    func testCaptureErrorsExposeMessage() {
        let service = AtlasCaptureService(
            captureFullScreen: { throw AtlasCaptureError.captureFailed("denied") },
            captureRegion: { _, _, _, _ in Data() }
        )

        XCTAssertThrowsError(try service.captureFullScreen()) { error in
            XCTAssertEqual(error.localizedDescription, "denied")
        }
    }
}
