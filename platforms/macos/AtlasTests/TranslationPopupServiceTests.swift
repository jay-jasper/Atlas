import XCTest
@testable import Atlas

private struct StubTranslator: ScreenshotTranslating {
    var shouldThrow = false
    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        if shouldThrow { throw NSError(domain: "t", code: 1) }
        return ScreenshotTranslationResult(
            sourceText: text,
            translatedText: "[\(targetLanguage)] \(text)",
            targetLanguage: targetLanguage
        )
    }
}

@MainActor
final class TranslationPopupServiceTests: XCTestCase {
    func testTranslateProducesResult() {
        let service = TranslationPopupService(translator: StubTranslator(), readPasteboard: { nil })
        service.sourceText = "hello"
        service.targetLanguage = "zh"
        service.translate()
        XCTAssertEqual(service.translatedText, "[zh] hello")
    }

    func testEmptyInputClearsResult() {
        let service = TranslationPopupService(translator: StubTranslator(), readPasteboard: { nil })
        service.sourceText = "   "
        service.translate()
        XCTAssertTrue(service.translatedText.isEmpty)
    }

    func testTranslateSelectionReadsClipboard() {
        let service = TranslationPopupService(translator: StubTranslator(), readPasteboard: { "bonjour" })
        service.targetLanguage = "en"
        service.translateSelection()
        XCTAssertEqual(service.sourceText, "bonjour")
        XCTAssertEqual(service.translatedText, "[en] bonjour")
    }

    func testTranslateSelectionWithEmptyClipboardSetsStatus() {
        let service = TranslationPopupService(translator: StubTranslator(), readPasteboard: { nil })
        service.translateSelection()
        XCTAssertFalse(service.statusMessage.isEmpty)
    }

    func testFailureSetsStatus() {
        let service = TranslationPopupService(translator: StubTranslator(shouldThrow: true), readPasteboard: { nil })
        service.sourceText = "x"
        service.translate()
        XCTAssertFalse(service.statusMessage.isEmpty)
        XCTAssertTrue(service.translatedText.isEmpty)
    }
}
