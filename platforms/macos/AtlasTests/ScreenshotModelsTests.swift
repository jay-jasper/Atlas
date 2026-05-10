import XCTest
@testable import Atlas

final class ScreenshotModelsTests: XCTestCase {
    func testAnnotationDefaults() {
        let annotation = ScreenshotAnnotation.rectangle(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            rect: CGRect(x: 10, y: 20, width: 30, height: 40),
            color: .red,
            lineWidth: 3
        )

        XCTAssertEqual(annotation.id.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(annotation.kind, .rectangle)
        XCTAssertEqual(annotation.bounds, CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    func testToolMetadata() {
        XCTAssertEqual(ScreenshotTool.rectangle.systemImage, "rectangle")
        XCTAssertEqual(ScreenshotTool.arrow.systemImage, "arrow.up.right")
        XCTAssertEqual(ScreenshotTool.pen.systemImage, "pencil")
        XCTAssertEqual(ScreenshotTool.text.systemImage, "textformat")
        XCTAssertEqual(ScreenshotTool.pixelate.systemImage, "checkerboard.rectangle")
    }
}
