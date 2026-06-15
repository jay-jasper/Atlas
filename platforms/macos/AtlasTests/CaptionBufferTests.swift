import XCTest
@testable import Atlas

@MainActor
final class CaptionBufferTests: XCTestCase {
    func testPartialShownThenCommitted() {
        var buffer = CaptionBuffer(maxCharacters: 100)
        buffer.updatePartial("hello wor")
        XCTAssertEqual(buffer.displayText, "hello wor")
        buffer.commit("hello world")
        XCTAssertEqual(buffer.displayText, "hello world")
        XCTAssertEqual(buffer.partial, "")
    }

    func testCommitsAccumulate() {
        var buffer = CaptionBuffer(maxCharacters: 100)
        buffer.commit("one")
        buffer.commit("two")
        XCTAssertEqual(buffer.displayText, "one two")
    }

    func testPartialAppendsToCommitted() {
        var buffer = CaptionBuffer(maxCharacters: 100)
        buffer.commit("committed text")
        buffer.updatePartial("partial")
        XCTAssertEqual(buffer.displayText, "committed text partial")
    }

    func testTrimsToBudgetByDroppingLeadingWords() {
        var buffer = CaptionBuffer(maxCharacters: 12)
        buffer.commit("alpha")
        buffer.commit("bravo")
        buffer.commit("charlie")
        // Should keep within budget, dropping the oldest words.
        XCTAssertLessThanOrEqual(buffer.displayText.count, 12)
        XCTAssertTrue(buffer.displayText.contains("charlie"))
    }

    func testClear() {
        var buffer = CaptionBuffer()
        buffer.commit("text")
        buffer.clear()
        XCTAssertEqual(buffer.displayText, "")
    }

    func testServiceAppliesPartialAndFinal() {
        let service = LiveCaptionService()
        service.applyPartial("typing")
        XCTAssertEqual(service.caption, "typing")
        service.applyFinal("typing done")
        XCTAssertEqual(service.caption, "typing done")
    }
}
