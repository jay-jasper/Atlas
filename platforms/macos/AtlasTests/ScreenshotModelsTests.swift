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

    func testArrowStandardizesBoundsAndKeepsPoints() {
        let start = CGPoint(x: 50, y: 80)
        let end = CGPoint(x: 10, y: 20)
        let annotation = ScreenshotAnnotation.arrow(from: start, to: end, color: .blue, lineWidth: 2)

        XCTAssertEqual(annotation.kind, .arrow)
        XCTAssertEqual(annotation.bounds, CGRect(x: 10, y: 20, width: 40, height: 60))
        XCTAssertEqual(annotation.color, .blue)
        XCTAssertEqual(annotation.lineWidth, 2)
        XCTAssertEqual(annotation.points, [start, end])
    }

    func testPenBoundsAndPoints() {
        let points = [
            CGPoint(x: 2, y: 3),
            CGPoint(x: 10, y: 4),
            CGPoint(x: 5, y: 12),
        ]
        let annotation = ScreenshotAnnotation.pen(points: points, color: .green, lineWidth: 4)

        XCTAssertEqual(annotation.kind, .pen)
        XCTAssertEqual(annotation.bounds, CGRect(x: 2, y: 3, width: 9, height: 10))
        XCTAssertEqual(annotation.color, .green)
        XCTAssertEqual(annotation.lineWidth, 4)
        XCTAssertEqual(annotation.points, points)
    }

    func testTextPayloadAndBounds() {
        let rect = CGRect(x: 12, y: 24, width: 100, height: 32)
        let annotation = ScreenshotAnnotation.text(value: "Hello", rect: rect, color: .yellow)

        XCTAssertEqual(annotation.kind, .text("Hello"))
        XCTAssertEqual(annotation.bounds, rect)
        XCTAssertEqual(annotation.color, .yellow)
        XCTAssertEqual(annotation.lineWidth, 1)
        XCTAssertEqual(annotation.points, [])
    }

    func testPixelateDefaults() {
        let rect = CGRect(x: 4, y: 8, width: 40, height: 20)
        let annotation = ScreenshotAnnotation.pixelate(rect: rect)

        XCTAssertEqual(annotation.kind, .pixelate)
        XCTAssertEqual(annotation.bounds, rect)
        XCTAssertEqual(annotation.color, .gray)
        XCTAssertEqual(annotation.lineWidth, 1)
        XCTAssertEqual(annotation.points, [])
    }

    func testAnnotationColorMetadata() {
        XCTAssertEqual(ScreenshotAnnotationColor.allCases.map(\.rawValue), [
            "red",
            "yellow",
            "green",
            "blue",
            "white",
            "black",
        ])

        XCTAssertEqual(ScreenshotAnnotationColor.red.title, "Red")
        XCTAssertEqual(ScreenshotAnnotationColor.blue.color, .blue)
        XCTAssertEqual(ScreenshotAnnotationColor.black.id, "black")
    }

    func testDefaultAnnotationStyleMatchesCurrentEditorBehavior() {
        let style = ScreenshotAnnotationStyle.defaultStyle

        XCTAssertEqual(style.colorChoice, .red)
        XCTAssertEqual(style.color, .red)
        XCTAssertEqual(style.lineWidth, 2)
    }

    func testAnnotationStyleClampsLineWidth() {
        XCTAssertEqual(ScreenshotAnnotationStyle(colorChoice: .green, lineWidth: 0).lineWidth, 1)
        XCTAssertEqual(ScreenshotAnnotationStyle(colorChoice: .green, lineWidth: 20).lineWidth, 12)
        XCTAssertEqual(ScreenshotAnnotationStyle(colorChoice: .green, lineWidth: 6).lineWidth, 6)
    }

    func testTextAnnotationDraftDefaultsToText() {
        let draft = ScreenshotTextAnnotationDraft()

        XCTAssertEqual(draft.rawValue, "Text")
        XCTAssertEqual(draft.annotationValue, "Text")
    }

    func testTextAnnotationDraftTrimsAnnotationValue() {
        let draft = ScreenshotTextAnnotationDraft(rawValue: "  Release 1.0  ")

        XCTAssertEqual(draft.rawValue, "  Release 1.0  ")
        XCTAssertEqual(draft.annotationValue, "Release 1.0")
    }

    func testTextAnnotationDraftFallsBackForBlankValues() {
        XCTAssertEqual(ScreenshotTextAnnotationDraft(rawValue: "").annotationValue, "Text")
        XCTAssertEqual(ScreenshotTextAnnotationDraft(rawValue: "   \n\t  ").annotationValue, "Text")
    }

    func testTextAnnotationDraftLimitsLength() {
        let draft = ScreenshotTextAnnotationDraft(rawValue: String(repeating: "A", count: 120))

        XCTAssertEqual(draft.annotationValue.count, ScreenshotTextAnnotationDraft.maximumLength)
        XCTAssertEqual(draft.annotationValue, String(repeating: "A", count: ScreenshotTextAnnotationDraft.maximumLength))
    }

    func testCapturedScreenshotInitialization() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let data = Data([0x89, 0x50, 0x4e, 0x47])
        let rect = CGRect(x: 1, y: 2, width: 300, height: 200)
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let screenshot = CapturedScreenshot(
            id: id,
            pngData: data,
            rect: rect,
            capturedAt: capturedAt
        )

        XCTAssertEqual(screenshot.id, id)
        XCTAssertEqual(screenshot.pngData, data)
        XCTAssertEqual(screenshot.rect, rect)
        XCTAssertEqual(screenshot.capturedAt, capturedAt)
    }
}
