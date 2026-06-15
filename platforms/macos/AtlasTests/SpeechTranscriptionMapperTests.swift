import XCTest
@testable import Atlas

@MainActor
final class SpeechTranscriptionMapperTests: XCTestCase {
    private func word(_ t: String, _ s: Int, _ e: Int) -> SpeechTranscriptionMapper.Word {
        .init(text: t, startMs: s, endMs: e)
    }

    func testBreaksOnSentenceEnd() {
        let words = [word("Hello", 0, 500), word("world.", 500, 1000), word("Next", 1200, 1500)]
        let segments = SpeechTranscriptionMapper.group(words: words)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0], TranscriptSegment(startMs: 0, endMs: 1000, text: "Hello world."))
        XCTAssertEqual(segments[1], TranscriptSegment(startMs: 1200, endMs: 1500, text: "Next"))
    }

    func testBreaksAtMaxWords() {
        let words = (0..<15).map { word("w\($0)", $0 * 100, $0 * 100 + 50) }
        let segments = SpeechTranscriptionMapper.group(words: words, maxWords: 5)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].text.split(separator: " ").count, 5)
    }

    func testTimestampsSpanFirstToLast() {
        let words = [word("a", 100, 200), word("b", 200, 400)]
        let segments = SpeechTranscriptionMapper.group(words: words, maxWords: 10)
        XCTAssertEqual(segments[0].startMs, 100)
        XCTAssertEqual(segments[0].endMs, 400)
    }

    func testEmptyInput() {
        XCTAssertTrue(SpeechTranscriptionMapper.group(words: []).isEmpty)
    }
}
