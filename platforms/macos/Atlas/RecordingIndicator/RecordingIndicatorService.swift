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
        let microphoneTypes: [AVCaptureDevice.DeviceType]
        let cameraTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            microphoneTypes = [.microphone]
            cameraTypes = [.builtInWideAngleCamera, .external]
        } else {
            microphoneTypes = [.builtInMicrophone]
            cameraTypes = [.builtInWideAngleCamera, .externalUnknown]
        }
        let mic = AVCaptureDevice.DiscoverySession(
            deviceTypes: microphoneTypes,
            mediaType: .audio,
            position: .unspecified
        ).devices.contains { $0.isInUseByAnotherApplication }
        let cam = AVCaptureDevice.DiscoverySession(
            deviceTypes: cameraTypes,
            mediaType: .video,
            position: .unspecified
        ).devices.contains { $0.isInUseByAnotherApplication }
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
