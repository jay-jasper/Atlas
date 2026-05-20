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

        XCTAssertEqual(layout.thumbnailSize, CGSize(width: 168, height: 104))
    }

    func testFramePlacesThumbnailNearBottomTrailingVisibleFrame() {
        let layout = FloatingScreenshotThumbnailLayout(
            imagePixelSize: CGSize(width: 400, height: 200),
            maxSize: CGSize(width: 200, height: 120),
            margin: 10
        )

        let frame = layout.frame(in: CGRect(x: 50, y: 80, width: 1000, height: 700))

        XCTAssertEqual(frame, CGRect(x: 840, y: 90, width: 200, height: 104))
    }

    func testInvalidImageSizeFallsBackToMaximumSize() {
        let layout = FloatingScreenshotThumbnailLayout(
            imagePixelSize: .zero,
            maxSize: CGSize(width: 220, height: 150),
            margin: 18
        )

        XCTAssertEqual(layout.thumbnailSize, CGSize(width: 220, height: 150))
    }

    func testThumbnailActionsHaveStableMetadata() {
        XCTAssertEqual(FloatingScreenshotThumbnailAction.allCases, [.open, .copy, .save, .dismiss])
        XCTAssertEqual(FloatingScreenshotThumbnailAction.open.title, "Open Editor")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.open.systemImage, "square.and.pencil")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.copy.title, "Copy")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.copy.systemImage, "doc.on.doc")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.save.title, "Save")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.save.systemImage, "square.and.arrow.down")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.dismiss.title, "Dismiss")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.dismiss.systemImage, "xmark")
    }

    func testActionResultStatusText() {
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.ready.statusText, "Ready")
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.openedEditor.statusText, "Opened editor")
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.copied.statusText, "Copied")
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.saved(filename: "Atlas.png").statusText, "Saved Atlas.png")
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.saveCancelled.statusText, "Save cancelled")
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.dismissed.statusText, "Dismissed")
    }

    func testActionStateAppliesResults() {
        var state = FloatingScreenshotThumbnailActionState()

        XCTAssertEqual(state.statusText, "Ready")
        state.apply(.copied)
        XCTAssertEqual(state.statusText, "Copied")
        state.apply(.saved(filename: "One.png"))
        XCTAssertEqual(state.statusText, "Saved One.png")
    }

    func testActionStateStatusTextChangesAfterEachResult() {
        var state = FloatingScreenshotThumbnailActionState()
        let results: [FloatingScreenshotThumbnailActionResult] = [
            .openedEditor,
            .copied,
            .saveCancelled,
            .dismissed,
        ]

        let statuses = results.map { result in
            state.apply(result)
            return state.statusText
        }

        XCTAssertEqual(statuses, [
            "Opened editor",
            "Copied",
            "Save cancelled",
            "Dismissed",
        ])
    }
}
