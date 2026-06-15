import XCTest
@testable import Atlas

@MainActor
final class NowPlayingParserTests: XCTestCase {
    func testParsesConstantNameKeys() {
        let info: [String: Any] = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Song",
            "kMRMediaRemoteNowPlayingInfoArtist": "Artist",
            "kMRMediaRemoteNowPlayingInfoAlbum": "Album",
            "kMRMediaRemoteNowPlayingInfoElapsedTime": NSNumber(value: 30.0),
            "kMRMediaRemoteNowPlayingInfoDuration": NSNumber(value: 200.0),
        ]
        let track = NowPlayingParser.parse(info: info, isPlaying: true)
        XCTAssertEqual(track?.title, "Song")
        XCTAssertEqual(track?.artist, "Artist")
        XCTAssertEqual(track?.duration, 200)
        XCTAssertEqual(track?.elapsed, 30)
        XCTAssertTrue(track?.isPlaying ?? false)
    }

    func testParsesShortFallbackKeys() {
        let info: [String: Any] = ["Title": "Quick", "Artist": "X"]
        XCTAssertEqual(NowPlayingParser.parse(info: info, isPlaying: false)?.title, "Quick")
    }

    func testNilWhenNoTitle() {
        XCTAssertNil(NowPlayingParser.parse(info: ["Artist": "X"], isPlaying: true))
        XCTAssertNil(NowPlayingParser.parse(info: [:], isPlaying: true))
    }
}
