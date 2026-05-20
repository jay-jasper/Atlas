import XCTest
@testable import Atlas

final class FloatingScreenshotThumbnailWindowTests: XCTestCase {
    func testThumbnailSizePreservesAspectRatioWithinMaximumSize() {
        let layout = FloatingScreenshotThumbnailLayout(
            imagePixelSize: CGSize(width: 1600, height: 900),
            maxSize: CGSize(width: 220, height: 150),
            margin: 18
        )

        XCTAssertEqual(layout.thumbnailSize.width, 220, accuracy: 0.01)
        XCTAssertEqual(layout.thumbnailSize.height, 123.75, accuracy: 0.01)
    }

    func testThumbnailSizeDoesNotUpscaleSmallImagesBelowMinimums() {
        let layout = FloatingScreenshotThumbnailLayout(
            imagePixelSize: CGSize(width: 80, height: 40),
            maxSize: CGSize(width: 220, height: 150),
            margin: 18
        )

        XCTAssertEqual(layout.thumbnailSize, CGSize(width: 96, height: 64))
    }

    func testFramePlacesThumbnailNearBottomTrailingVisibleFrame() {
        let layout = FloatingScreenshotThumbnailLayout(
            imagePixelSize: CGSize(width: 400, height: 200),
            maxSize: CGSize(width: 200, height: 120),
            margin: 10
        )

        let frame = layout.frame(in: CGRect(x: 50, y: 80, width: 1000, height: 700))

        XCTAssertEqual(frame, CGRect(x: 840, y: 90, width: 200, height: 100))
    }

    func testInvalidImageSizeFallsBackToMaximumSize() {
        let layout = FloatingScreenshotThumbnailLayout(
            imagePixelSize: .zero,
            maxSize: CGSize(width: 220, height: 150),
            margin: 18
        )

        XCTAssertEqual(layout.thumbnailSize, CGSize(width: 220, height: 150))
    }
}
