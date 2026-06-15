import XCTest
@testable import Atlas

@MainActor
final class NowPlayingFormatterTests: XCTestCase {
    private let track = NowPlayingTrack(
        title: "Song", artist: "Artist", album: "Album",
        isPlaying: true, elapsed: 65, duration: 200
    )

    func testProgress() {
        XCTAssertEqual(NowPlayingFormatter.progress(track), 0.325, accuracy: 0.001)
        XCTAssertEqual(NowPlayingFormatter.progress(.none), 0)
    }

    func testTimeLabel() {
        XCTAssertEqual(NowPlayingFormatter.timeLabel(track), "1:05 / 3:20")
    }

    func testSubtitleJoinsArtistAndAlbum() {
        XCTAssertEqual(NowPlayingFormatter.subtitle(track), "Artist — Album")
        let noAlbum = NowPlayingTrack(title: "S", artist: "A", album: "", isPlaying: false, elapsed: 0, duration: 0)
        XCTAssertEqual(NowPlayingFormatter.subtitle(noAlbum), "A")
    }

    func testProgressClamps() {
        let over = NowPlayingTrack(title: "x", artist: "", album: "", isPlaying: true, elapsed: 300, duration: 200)
        XCTAssertEqual(NowPlayingFormatter.progress(over), 1)
    }
}

private struct StubProvider: NowPlayingProviding {
    let track: NowPlayingTrack?
    func current() -> NowPlayingTrack? { track }
}

@MainActor
final class NowPlayingServiceTests: XCTestCase {
    func testReflectsProvider() {
        let track = NowPlayingTrack(title: "Hit", artist: "X", album: "Y", isPlaying: true, elapsed: 1, duration: 10)
        let service = NowPlayingService(provider: StubProvider(track: track))
        XCTAssertTrue(service.track.hasTrack)
        XCTAssertEqual(service.track.title, "Hit")
    }

    func testNoTrackSetsStatus() {
        let service = NowPlayingService(provider: StubProvider(track: nil))
        XCTAssertFalse(service.track.hasTrack)
        XCTAssertFalse(service.statusMessage.isEmpty)
    }
}
