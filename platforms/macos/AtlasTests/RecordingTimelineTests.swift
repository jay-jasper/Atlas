import XCTest
@testable import Atlas

@MainActor
final class RecordingTimelineTests: XCTestCase {
    func testInitialClipSpansSource() {
        let timeline = RecordingTimeline(sourceDurationMs: 10000)
        XCTAssertEqual(timeline.clips.count, 1)
        XCTAssertEqual(timeline.totalDurationMs, 10000)
    }

    func testTrimClampsAndUpdatesDuration() {
        var timeline = RecordingTimeline(sourceDurationMs: 10000)
        let id = timeline.clips[0].id
        timeline.trim(id: id, startMs: 2000, endMs: 6000)
        XCTAssertEqual(timeline.totalDurationMs, 4000)
        // Reversed args are normalized.
        timeline.trim(id: id, startMs: 8000, endMs: 3000)
        XCTAssertEqual(timeline.clips[0].sourceStartMs, 3000)
        XCTAssertEqual(timeline.clips[0].sourceEndMs, 8000)
    }

    func testSplitProducesTwoAdjacentClips() {
        var timeline = RecordingTimeline(sourceDurationMs: 10000)
        let id = timeline.clips[0].id
        timeline.split(id: id, atClipOffsetMs: 4000)
        XCTAssertEqual(timeline.clips.count, 2)
        XCTAssertEqual(timeline.clips[0].sourceEndMs, 4000)
        XCTAssertEqual(timeline.clips[1].sourceStartMs, 4000)
        // Output duration is unchanged by a split.
        XCTAssertEqual(timeline.totalDurationMs, 10000)
    }

    func testSplitAtBoundaryIsNoOp() {
        var timeline = RecordingTimeline(sourceDurationMs: 5000)
        let id = timeline.clips[0].id
        timeline.split(id: id, atClipOffsetMs: 0)
        timeline.split(id: id, atClipOffsetMs: 5000)
        XCTAssertEqual(timeline.clips.count, 1)
    }

    func testRemoveAndExportSpans() {
        var timeline = RecordingTimeline(sourceDurationMs: 9000)
        let id = timeline.clips[0].id
        timeline.split(id: id, atClipOffsetMs: 3000)
        timeline.remove(id: timeline.clips[0].id)
        XCTAssertEqual(timeline.clips.count, 1)
        XCTAssertEqual(timeline.exportSpans.map(\.start), [3000])
    }

    func testMoveReorders() {
        var timeline = RecordingTimeline(clips: [
            RecordingClip(sourceStartMs: 0, sourceEndMs: 1000),
            RecordingClip(sourceStartMs: 1000, sourceEndMs: 2000),
        ])
        let first = timeline.clips[0].id
        timeline.move(from: 0, to: 2)
        XCTAssertEqual(timeline.clips.last?.id, first)
    }
}
