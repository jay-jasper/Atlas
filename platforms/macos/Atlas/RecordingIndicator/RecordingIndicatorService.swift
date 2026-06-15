import AVFoundation
import Foundation

/// Detects which capture sources are active. Injected for testing.
protocol RecordingSourceDetecting {
    func currentStatus() -> RecordingStatus
}

/// Live detector: AVCaptureDevice "in use" flags for mic/camera. Screen capture
/// detection is best-effort and reported separately by the screenshot module.
struct LiveRecordingSourceDetector: RecordingSourceDetecting {
    func currentStatus() -> RecordingStatus {
        let mic = AVCaptureDevice.devices(for: .audio).contains { $0.isInUseByAnotherApplication }
        let cam = AVCaptureDevice.devices(for: .video).contains { $0.isInUseByAnotherApplication }
        return RecordingStatus(microphone: mic, camera: cam, screen: false)
    }
}

@MainActor
final class RecordingIndicatorService: ObservableObject {
    @Published private(set) var status: RecordingStatus = .idle

    private let detector: RecordingSourceDetecting

    init(detector: RecordingSourceDetecting = LiveRecordingSourceDetector()) {
        self.detector = detector
        refresh()
    }

    func refresh() {
        status = detector.currentStatus()
    }

    /// Lets the screenshot/recording module report screen capture explicitly.
    func setScreenRecording(_ active: Bool) {
        status.screen = active
    }
}
