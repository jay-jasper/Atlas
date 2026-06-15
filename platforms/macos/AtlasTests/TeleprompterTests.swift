import XCTest
@testable import Atlas

@MainActor
final class TeleprompterEngineTests: XCTestCase {
    func testOffsetScalesWithTimeAndSpeed() {
        let offset = TeleprompterEngine.offset(elapsed: 2, speed: 50, contentHeight: 1000, viewportHeight: 100)
        XCTAssertEqual(offset, 100) // 2s * 50pt/s
    }

    func testOffsetClampsAtEnd() {
        let offset = TeleprompterEngine.offset(elapsed: 1000, speed: 50, contentHeight: 500, viewportHeight: 100)
        XCTAssertEqual(offset, 400) // contentHeight - viewportHeight
    }

    func testProgress() {
        XCTAssertEqual(TeleprompterEngine.progress(offset: 200, contentHeight: 500, viewportHeight: 100), 0.5, accuracy: 0.001)
        // No scrollable region -> fully complete.
        XCTAssertEqual(TeleprompterEngine.progress(offset: 0, contentHeight: 50, viewportHeight: 100), 1)
    }

    func testIsComplete() {
        XCTAssertTrue(TeleprompterEngine.isComplete(offset: 400, contentHeight: 500, viewportHeight: 100))
        XCTAssertFalse(TeleprompterEngine.isComplete(offset: 100, contentHeight: 500, viewportHeight: 100))
    }
}

@MainActor
final class TeleprompterServiceTests: XCTestCase {
    func testTickAdvancesOffsetAndStopsAtEnd() {
        var clock = Date(timeIntervalSince1970: 0)
        let service = TeleprompterService(now: { clock })
        service.contentHeight = 500
        service.viewportHeight = 100
        service.speed = 100
        service.start()
        XCTAssertTrue(service.isScrolling)

        clock = Date(timeIntervalSince1970: 2)
        service.tick(at: clock)
        XCTAssertEqual(service.offset, 200)

        // Past the end -> clamps and pauses.
        clock = Date(timeIntervalSince1970: 100)
        service.tick(at: clock)
        XCTAssertEqual(service.offset, 400)
        XCTAssertFalse(service.isScrolling)
    }

    func testReset() {
        let service = TeleprompterService(now: { Date(timeIntervalSince1970: 0) })
        service.contentHeight = 500
        service.viewportHeight = 100
        service.start()
        service.reset()
        XCTAssertEqual(service.offset, 0)
        XCTAssertFalse(service.isScrolling)
    }
}
