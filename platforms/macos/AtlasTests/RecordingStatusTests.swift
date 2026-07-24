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

final class ScreenRecordingGeometryTests: XCTestCase {
    func testSourceRectClipsSelectionToDisplayBounds() {
        let rect = ScreenRecordingGeometry.sourceRect(
            selection: CGRect(x: -10, y: 20, width: 210, height: 100),
            screenSize: CGSize(width: 160, height: 120)
        )

        XCTAssertEqual(rect, CGRect(x: 0, y: 20, width: 160, height: 100))
    }

    func testGlobalRectFlipsSelectionFromTopLeftToAppKitCoordinates() {
        let rect = ScreenRecordingGeometry.appKitGlobalRect(
            sourceRect: CGRect(x: 40, y: 30, width: 320, height: 180),
            screenFrame: CGRect(x: 100, y: 50, width: 1440, height: 900)
        )

        XCTAssertEqual(rect, CGRect(x: 140, y: 740, width: 320, height: 180))
    }

    func testPixelDimensionsAreEvenForH264() {
        let size = ScreenRecordingGeometry.evenPixelSize(
            sourceRect: CGRect(x: 0, y: 0, width: 101.5, height: 50.5),
            scale: 2
        )

        XCTAssertEqual(size.width, 202)
        XCTAssertEqual(size.height, 100)
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
