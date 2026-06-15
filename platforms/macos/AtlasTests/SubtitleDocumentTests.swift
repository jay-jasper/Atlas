import XCTest
@testable import Atlas

@MainActor
final class SubtitleDocumentTests: XCTestCase {
    private let srt = """
    1
    00:00:01,000 --> 00:00:04,000
    Hello world

    2
    00:00:05,500 --> 00:00:07,250
    Second line
    """

    func testParseSRT() {
        let cues = SubtitleDocument.parse(srt, format: .srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0], SubtitleCue(start: 1000, end: 4000, text: "Hello world"))
        XCTAssertEqual(cues[1], SubtitleCue(start: 5500, end: 7250, text: "Second line"))
    }

    func testParseTimestamp() {
        XCTAssertEqual(SubtitleDocument.parseTimestamp("01:02:03,500"), 3723500)
        XCTAssertEqual(SubtitleDocument.parseTimestamp("00:00:07.250"), 7250)
    }

    func testSerializeSRTRoundTrip() {
        let cues = SubtitleDocument.parse(srt, format: .srt)
        let serialized = SubtitleDocument.serialize(cues, format: .srt)
        let reparsed = SubtitleDocument.parse(serialized, format: .srt)
        XCTAssertEqual(reparsed, cues)
    }

    func testConvertSRTtoVTT() {
        let vtt = SubtitleDocument.convert(srt, from: .srt, to: .vtt)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT"))
        XCTAssertTrue(vtt.contains("00:00:01.000 --> 00:00:04.000"))
        // Round-trips back through VTT parse.
        XCTAssertEqual(SubtitleDocument.parse(vtt, format: .vtt).count, 2)
    }

    func testShift() {
        let cues = SubtitleDocument.parse(srt, format: .srt)
        let shifted = SubtitleDocument.shift(cues, byMillis: 500)
        XCTAssertEqual(shifted[0].start, 1500)
        XCTAssertEqual(shifted[0].end, 4500)
    }

    func testShiftClampsAtZero() {
        let cues = [SubtitleCue(start: 200, end: 1000, text: "x")]
        let shifted = SubtitleDocument.shift(cues, byMillis: -500)
        XCTAssertEqual(shifted[0].start, 0)
        XCTAssertEqual(shifted[0].end, 500)
    }

    func testServiceProcess() {
        let service = SubtitleService()
        service.inputText = srt
        service.sourceFormat = .srt
        service.targetFormat = .vtt
        service.shiftMillis = 1000
        service.process()
        XCTAssertEqual(service.cueCount, 2)
        XCTAssertTrue(service.outputText.contains("00:00:02.000 --> 00:00:05.000"))
    }
}
