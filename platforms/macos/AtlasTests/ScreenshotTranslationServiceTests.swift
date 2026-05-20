import XCTest
@testable import Atlas

final class ScreenshotTranslationServiceTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.translationService = LocalPlaceholderScreenshotTranslationService()
        super.tearDown()
    }

    func testResultStoresSourceTranslatedAndTargetLanguage() {
        let result = ScreenshotTranslationResult(
            sourceText: "Hello",
            translatedText: "Bonjour",
            targetLanguage: "fr"
        )

        XCTAssertEqual(result.sourceText, "Hello")
        XCTAssertEqual(result.translatedText, "Bonjour")
        XCTAssertEqual(result.targetLanguage, "fr")
    }

    func testEmptyTextErrorMessage() {
        XCTAssertEqual(
            ScreenshotTranslationError.emptyText.localizedDescription,
            "Screenshot text is empty and cannot be translated"
        )
    }

    func testPlaceholderRejectsNonEmptyTextWithUnsupportedMessage() {
        let service = LocalPlaceholderScreenshotTranslationService()

        XCTAssertThrowsError(try service.translate("Hello", targetLanguage: "fr")) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Local screenshot translation is not supported yet"
            )
        }
    }

    func testPlaceholderRejectsBlankTextWithEmptyTextMessage() {
        let service = LocalPlaceholderScreenshotTranslationService()

        XCTAssertThrowsError(try service.translate("   \n", targetLanguage: "fr")) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Screenshot text is empty and cannot be translated"
            )
        }
    }

    func testBridgeUsesInjectedTranslationService() throws {
        AtlasBridge.translationService = StubScreenshotTranslationService(
            result: ScreenshotTranslationResult(
                sourceText: "Hello",
                translatedText: "Bonjour",
                targetLanguage: "fr"
            )
        )

        let result = try AtlasBridge.translateScreenshotText("Hello", targetLanguage: "fr")

        XCTAssertEqual(result.sourceText, "Hello")
        XCTAssertEqual(result.translatedText, "Bonjour")
        XCTAssertEqual(result.targetLanguage, "fr")
    }
}

private struct StubScreenshotTranslationService: ScreenshotTranslating {
    let result: ScreenshotTranslationResult

    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        result
    }
}
