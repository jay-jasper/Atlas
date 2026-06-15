import XCTest
@testable import Atlas

@MainActor
final class TranscriptionModelTests: XCTestCase {
    func testModelCatalog() {
        XCTAssertEqual(WhisperModel.allCases.count, 5)
        XCTAssertEqual(WhisperModel.tiny.sizeMB, 75)
        XCTAssertTrue(WhisperModel.large.downloadURL.contains("ggml-large.bin"))
        XCTAssertLessThan(WhisperModel.tiny.accuracyRank, WhisperModel.large.accuracyRank)
    }

    func testSRTExportReusesSubtitleSerializer() {
        let segments = [
            TranscriptSegment(startMs: 0, endMs: 2000, text: "Hello"),
            TranscriptSegment(startMs: 2000, endMs: 4000, text: "World"),
        ]
        let srt = TranscriptionFormatter.srt(segments)
        XCTAssertTrue(srt.contains("00:00:00,000 --> 00:00:02,000"))
        XCTAssertTrue(srt.contains("Hello"))
        // Round-trips through the subtitle parser.
        XCTAssertEqual(SubtitleDocument.parse(srt, format: .srt).count, 2)
    }

    func testPlainText() {
        let segments = [
            TranscriptSegment(startMs: 0, endMs: 1, text: "one"),
            TranscriptSegment(startMs: 1, endMs: 2, text: "two"),
        ]
        XCTAssertEqual(TranscriptionFormatter.plainText(segments), "one two")
    }
}

private struct StubTranscriber: Transcribing {
    let segments: [TranscriptSegment]
    func transcribe(fileURL: URL, model: WhisperModel) throws -> [TranscriptSegment] { segments }
}

@MainActor
final class TranscriptionServiceTests: XCTestCase {
    func testTranscribePublishesSegments() async {
        let segments = [TranscriptSegment(startMs: 0, endMs: 1000, text: "hi")]
        let service = TranscriptionService(transcriber: StubTranscriber(segments: segments))
        service.transcribe(url: URL(fileURLWithPath: "/tmp/a.wav"))
        // Wait for the detached task to publish.
        for _ in 0..<50 where service.isTranscribing { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(service.segments, segments)
        XCTAssertFalse(service.isTranscribing)
    }

    func testUnavailableTranscriberSetsStatus() async {
        let service = TranscriptionService(transcriber: UnavailableTranscriber())
        service.transcribe(url: URL(fileURLWithPath: "/tmp/a.wav"))
        for _ in 0..<50 where service.isTranscribing { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(service.segments.isEmpty)
        XCTAssertFalse(service.statusMessage.isEmpty)
    }
}
