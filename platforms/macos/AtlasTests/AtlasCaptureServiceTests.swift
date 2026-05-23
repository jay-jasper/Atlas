import XCTest
@testable import Atlas

final class AtlasCaptureServiceTests: XCTestCase {
    func testCaptureRegionUsesInjectedFunction() throws {
        let expected = Data([1, 2, 3])
        let logger = FakeCapturePrivacyPulseAccessLogger()
        let service = AtlasCaptureService(
            captureFullScreen: { Data([9]) },
            captureRegion: { x, y, width, height in
                XCTAssertEqual(x, 10)
                XCTAssertEqual(y, 20)
                XCTAssertEqual(width, 30)
                XCTAssertEqual(height, 40)
                return expected
            },
            accessLogger: logger
        )

        let data = try service.captureRegion(.init(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(data, expected)
        XCTAssertEqual(logger.events.map(\.title), ["Screen Capture"])
        XCTAssertEqual(logger.events.first?.category, .screenRecording)
    }

    func testCaptureFullScreenLogsScreenRecordingAttempt() throws {
        let logger = FakeCapturePrivacyPulseAccessLogger()
        let service = AtlasCaptureService(
            captureFullScreen: { Data([9]) },
            captureRegion: { _, _, _, _ in Data() },
            accessLogger: logger
        )

        _ = try service.captureFullScreen()

        XCTAssertEqual(logger.events.map(\.title), ["Screen Capture"])
        XCTAssertEqual(logger.events.first?.category, .screenRecording)
    }

    func testCaptureErrorsExposeMessage() {
        let service = AtlasCaptureService(
            captureFullScreen: { throw AtlasCaptureError.captureFailed("denied") },
            captureRegion: { _, _, _, _ in Data() }
        )

        XCTAssertThrowsError(try service.captureFullScreen()) { error in
            XCTAssertEqual(error.localizedDescription, "denied")
        }
    }
}

private final class FakeCapturePrivacyPulseAccessLogger: PrivacyPulseAccessLogging {
    struct Event: Equatable {
        let category: PrivacyPulseCategory
        let title: String
        let detail: String
    }

    private(set) var events: [Event] = []

    func record(category: PrivacyPulseCategory, title: String, detail: String) {
        events.append(Event(category: category, title: title, detail: detail))
    }
}
