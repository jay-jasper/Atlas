import CoreMedia
import XCTest
@testable import Atlas

final class RecordingExporterTests: XCTestCase {
    func testTimeRangesFromSpans() {
        let ranges = RecordingExporter.timeRanges(forSpans: [(start: 0, end: 1500), (start: 3000, end: 4000)])

        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].start, CMTime(value: 0, timescale: 1000))
        XCTAssertEqual(ranges[0].duration, CMTime(value: 1500, timescale: 1000))
        XCTAssertEqual(ranges[1].start, CMTime(value: 3000, timescale: 1000))
        XCTAssertEqual(ranges[1].duration, CMTime(value: 1000, timescale: 1000))
    }

    func testTimeRangesDropInvalidSpans() {
        let ranges = RecordingExporter.timeRanges(forSpans: [
            (start: 100, end: 100),
            (start: 200, end: 150),
            (start: -50, end: 100),
            (start: 500, end: 900),
        ])
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].start.value, 500)
    }

    func testTimelineSpansFeedExporter() {
        var timeline = RecordingTimeline(sourceDurationMs: 10_000)
        let firstID = timeline.clips[0].id
        timeline.split(id: firstID, atClipOffsetMs: 4000)
        timeline.remove(id: timeline.clips[0].id)

        let ranges = RecordingExporter.timeRanges(forSpans: timeline.exportSpans)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].start.value, 4000)
        XCTAssertEqual(ranges[0].duration.value, 6000)
    }
}
