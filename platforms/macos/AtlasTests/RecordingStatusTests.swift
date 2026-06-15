import XCTest
@testable import Atlas

@MainActor
final class RecordingStatusTests: XCTestCase {
    func testIdleIsInactive() {
        XCTAssertFalse(RecordingStatus.idle.isActive)
        XCTAssertEqual(RecordingStatus.idle.label, "Not recording")
    }

    func testActiveSourcesOrder() {
        let status = RecordingStatus(microphone: true, camera: true, screen: true)
        XCTAssertEqual(status.activeSources, ["Camera", "Microphone", "Screen"])
        XCTAssertEqual(status.label, "Recording: Camera, Microphone, Screen")
    }

    func testSystemImagePriority() {
        XCTAssertEqual(RecordingStatus(microphone: true, camera: true, screen: false).systemImage, "video.fill")
        XCTAssertEqual(RecordingStatus(microphone: true, camera: false, screen: true).systemImage, "rectangle.dashed.badge.record")
        XCTAssertEqual(RecordingStatus(microphone: true, camera: false, screen: false).systemImage, "mic.fill")
    }
}

private struct StubDetector: RecordingSourceDetecting {
    let status: RecordingStatus
    func currentStatus() -> RecordingStatus { status }
}

@MainActor
final class RecordingIndicatorServiceTests: XCTestCase {
    func testReflectsDetector() {
        let service = RecordingIndicatorService(detector: StubDetector(
            status: RecordingStatus(microphone: true, camera: false, screen: false)
        ))
        XCTAssertTrue(service.status.microphone)
        XCTAssertTrue(service.status.isActive)
    }

    func testScreenRecordingOverride() {
        let service = RecordingIndicatorService(detector: StubDetector(status: .idle))
        XCTAssertFalse(service.status.isActive)
        service.setScreenRecording(true)
        XCTAssertTrue(service.status.screen)
        XCTAssertTrue(service.status.isActive)
    }
}
