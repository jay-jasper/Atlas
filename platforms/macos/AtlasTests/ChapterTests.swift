import XCTest
@testable import Atlas

@MainActor
final class ChapterExporterTests: XCTestCase {
    private let markers = [
        ChapterMarker(seconds: 0, title: "Intro"),
        ChapterMarker(seconds: 95, title: "Topic One"),
        ChapterMarker(seconds: 3725, title: "Wrap Up"),
    ]

    func testYouTubeFormatUsesHoursWhenNeeded() {
        let output = ChapterExporter.export(markers, as: .youtube)
        let lines = output.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "0:00:00 Intro")
        XCTAssertEqual(lines[1], "0:01:35 Topic One")
        XCTAssertEqual(lines[2], "1:02:05 Wrap Up")
    }

    func testYouTubeShortFormOmitsHours() {
        let output = ChapterExporter.export([
            ChapterMarker(seconds: 0, title: "A"),
            ChapterMarker(seconds: 65, title: "B"),
        ], as: .youtube)
        XCTAssertEqual(output, "0:00 A\n1:05 B")
    }

    func testSRTFormat() {
        let output = ChapterExporter.export([
            ChapterMarker(seconds: 0, title: "A"),
            ChapterMarker(seconds: 10, title: "B"),
        ], as: .srt)
        XCTAssertTrue(output.contains("00:00:00,000 --> 00:00:10,000"))
        XCTAssertTrue(output.contains("1\n"))
    }

    func testSortsByTime() {
        let output = ChapterExporter.export([
            ChapterMarker(seconds: 100, title: "Late"),
            ChapterMarker(seconds: 10, title: "Early"),
        ], as: .podcast)
        XCTAssertTrue(output.hasPrefix("(0:00:10) Early"))
    }
}

@MainActor
final class ChapterServiceTests: XCTestCase {
    func testMarkUsesElapsedTime() {
        var clock = Date(timeIntervalSince1970: 1000)
        let service = ChapterService(now: { clock })
        service.start()
        clock = Date(timeIntervalSince1970: 1095)
        service.mark(title: "Topic")
        XCTAssertEqual(service.markers.count, 1)
        XCTAssertEqual(service.markers[0].seconds, 95)
        XCTAssertEqual(service.markers[0].title, "Topic")
    }

    func testMarkDefaultsTitle() {
        var clock = Date(timeIntervalSince1970: 0)
        let service = ChapterService(now: { clock })
        service.start()
        clock = Date(timeIntervalSince1970: 5)
        service.mark(title: "   ")
        XCTAssertEqual(service.markers[0].title, "Chapter 1")
    }

    func testMarkIgnoredWhenNotRecording() {
        let service = ChapterService()
        service.mark(title: "X")
        XCTAssertTrue(service.markers.isEmpty)
    }
}
