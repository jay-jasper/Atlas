import XCTest
@testable import Atlas

@MainActor
final class AspectRatioGuideTests: XCTestCase {
    func testSquareFitsInWideContainer() {
        let rect = AspectRatioGuide.fittedRect(preset: .square1x1, in: CGSize(width: 200, height: 100))
        // Height-constrained: 100x100 centered horizontally.
        XCTAssertEqual(rect.size, CGSize(width: 100, height: 100))
        XCTAssertEqual(rect.origin.x, 50, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.001)
    }

    func testVerticalFitsInWideContainer() {
        // 9:16 in a 160x90 container -> width-constrained? ratio 0.5625, container ratio 1.78
        let rect = AspectRatioGuide.fittedRect(preset: .vertical9x16, in: CGSize(width: 160, height: 90))
        XCTAssertEqual(rect.height, 90, accuracy: 0.001)
        XCTAssertEqual(rect.width, 90 * (9.0 / 16.0), accuracy: 0.001)
        XCTAssertEqual(rect.midX, 80, accuracy: 0.001)
    }

    func testWideFitsInTallContainer() {
        // 16:9 in a 100x200 container -> width-constrained.
        let rect = AspectRatioGuide.fittedRect(preset: .wide16x9, in: CGSize(width: 100, height: 200))
        XCTAssertEqual(rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(rect.height, 100 / (16.0 / 9.0), accuracy: 0.001)
        XCTAssertEqual(rect.midY, 100, accuracy: 0.001)
    }

    func testZeroContainerReturnsZero() {
        XCTAssertEqual(AspectRatioGuide.fittedRect(preset: .square1x1, in: .zero), .zero)
    }

    func testServiceRectUsesSelectedPreset() {
        let service = AspectGuideService()
        service.selectedPreset = .square1x1
        let rect = service.rect(in: CGSize(width: 100, height: 100))
        XCTAssertEqual(rect.size, CGSize(width: 100, height: 100))
    }

    func testToggleOverlay() {
        let service = AspectGuideService()
        XCTAssertFalse(service.isOverlayVisible)
        service.toggleOverlay()
        XCTAssertTrue(service.isOverlayVisible)
    }
}
