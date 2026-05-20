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

    func testBridgePassesContentViewTranslationTargetToInjectedService() throws {
        let service = CapturingScreenshotTranslationService(
            result: ScreenshotTranslationResult(
                sourceText: "Hola",
                translatedText: "Hello",
                targetLanguage: "English"
            )
        )
        AtlasBridge.translationService = service

        let result = try AtlasBridge.translateScreenshotText("Hola", targetLanguage: "English")

        XCTAssertEqual(service.receivedText, "Hola")
        XCTAssertEqual(service.receivedTargetLanguage, "English")
        XCTAssertEqual(result.translatedText, "Hello")
        XCTAssertEqual(result.targetLanguage, "English")
    }
}

private struct StubScreenshotTranslationService: ScreenshotTranslating {
    let result: ScreenshotTranslationResult

    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        result
    }
}

private final class CapturingScreenshotTranslationService: ScreenshotTranslating {
    let result: ScreenshotTranslationResult
    private(set) var receivedText: String?
    private(set) var receivedTargetLanguage: String?

    init(result: ScreenshotTranslationResult) {
        self.result = result
    }

    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        receivedText = text
        receivedTargetLanguage = targetLanguage
        return result
    }
}
