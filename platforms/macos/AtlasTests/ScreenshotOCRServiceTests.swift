import XCTest
@testable import Atlas

final class ScreenshotOCRServiceTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.ocrService = VisionScreenshotOCRService()
        super.tearDown()
    }

    func testResultTrimsAndJoinsLines() {
        let result = ScreenshotOCRResult(lines: ["  Hello ", "", "World\n"])

        XCTAssertEqual(result.lines, ["Hello", "World"])
        XCTAssertEqual(result.text, "Hello\nWorld")
    }

    func testBridgeUsesInjectedOCRService() throws {
        AtlasBridge.ocrService = StubOCRService(result: ScreenshotOCRResult(lines: ["Atlas", "OCR"]))

        let result = try AtlasBridge.recognizeText(in: Data([1, 2, 3]))

        XCTAssertEqual(result.text, "Atlas\nOCR")
    }

    func testInvalidImageErrorMessage() {
        XCTAssertEqual(
            ScreenshotOCRError.invalidImage.localizedDescription,
            "Screenshot image could not be decoded for OCR"
        )
    }
}

private struct StubOCRService: ScreenshotOCRProviding {
    let result: ScreenshotOCRResult

    func recognizeText(in imageData: Data) throws -> ScreenshotOCRResult {
        result
    }
}
