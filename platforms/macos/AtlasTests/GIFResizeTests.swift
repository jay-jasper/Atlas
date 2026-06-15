import XCTest
@testable import Atlas

@MainActor
final class GIFResizeTests: XCTestCase {
    func testScaled() {
        XCTAssertEqual(GIFResize.scaled(CGSize(width: 200, height: 100), by: 0.5), CGSize(width: 100, height: 50))
    }

    func testScaledNeverZero() {
        XCTAssertEqual(GIFResize.scaled(CGSize(width: 2, height: 2), by: 0.1), CGSize(width: 1, height: 1))
    }

    func testFittedDownscalesPreservingAspect() {
        let result = GIFResize.fitted(CGSize(width: 800, height: 400), maxDimension: 400)
        XCTAssertEqual(result, CGSize(width: 400, height: 200))
    }

    func testFittedNeverUpscales() {
        let source = CGSize(width: 100, height: 50)
        XCTAssertEqual(GIFResize.fitted(source, maxDimension: 1000), source)
    }

    func testFrameDelayClampsToGIFGranularity() {
        XCTAssertEqual(GIFResize.frameDelay(targetFPS: 10), 0.1, accuracy: 0.001)
        XCTAssertEqual(GIFResize.frameDelay(targetFPS: 1000), 0.02, accuracy: 0.001) // clamped
        XCTAssertEqual(GIFResize.frameDelay(targetFPS: 0), 0.1, accuracy: 0.001) // fallback
    }

    func testServiceTargetSizeCombinesScaleAndCap() {
        let service = GIFProcessingService()
        service.scale = 0.5
        service.maxDimension = 0
        XCTAssertEqual(service.targetSize(for: CGSize(width: 400, height: 200)), CGSize(width: 200, height: 100))

        service.scale = 1.0
        service.maxDimension = 100
        XCTAssertEqual(service.targetSize(for: CGSize(width: 400, height: 200)), CGSize(width: 100, height: 50))
    }
}
