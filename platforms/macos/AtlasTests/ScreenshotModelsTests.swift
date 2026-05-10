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
        XCTAssertEqual(annotation.color, .red)
        XCTAssertEqual(annotation.lineWidth, 3)
        XCTAssertEqual(annotation.points, [])
    }

    func testToolMetadata() {
        XCTAssertEqual(ScreenshotTool.rectangle.systemImage, "rectangle")
        XCTAssertEqual(ScreenshotTool.arrow.systemImage, "arrow.up.right")
        XCTAssertEqual(ScreenshotTool.pen.systemImage, "pencil")
        XCTAssertEqual(ScreenshotTool.text.systemImage, "textformat")
        XCTAssertEqual(ScreenshotTool.pixelate.systemImage, "checkerboard.rectangle")

        XCTAssertEqual(ScreenshotTool.rectangle.title, "Rectangle")
        XCTAssertEqual(ScreenshotTool.arrow.title, "Arrow")
        XCTAssertEqual(ScreenshotTool.pen.title, "Pen")
        XCTAssertEqual(ScreenshotTool.text.title, "Text")
        XCTAssertEqual(ScreenshotTool.pixelate.title, "Pixelate")

        XCTAssertEqual(ScreenshotTool.rectangle.id, "rectangle")
        XCTAssertEqual(ScreenshotTool.arrow.id, "arrow")
        XCTAssertEqual(ScreenshotTool.pen.id, "pen")
        XCTAssertEqual(ScreenshotTool.text.id, "text")
        XCTAssertEqual(ScreenshotTool.pixelate.id, "pixelate")

        XCTAssertEqual(ScreenshotTool.allCases, [.rectangle, .arrow, .pen, .text, .pixelate])
    }
}
