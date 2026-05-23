import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

struct PrivacyPulseSystemStatusProvider: PrivacyPulseStatusProviding {
    private let accessLogger: PrivacyPulseAccessLogging

    init(accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()) {
        self.accessLogger = accessLogger
    }

    func cameraStatus() -> PrivacyPulseStatus {
        status(from: AVCaptureDevice.authorizationStatus(for: .video))
    }

    func microphoneStatus() -> PrivacyPulseStatus {
        status(from: AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func screenRecordingStatus() -> PrivacyPulseStatus {
        accessLogger.record(
            category: .screenRecording,
            title: "Screen Recording Check",
            detail: "Atlas checked Screen Recording permission status"
        )
        return CGPreflightScreenCaptureAccess() ? PrivacyPulseStatus.allowed : PrivacyPulseStatus.denied
    }

    func accessibilityStatus() -> PrivacyPulseStatus {
        accessLogger.record(
            category: .accessibility,
            title: "Accessibility Check",
            detail: "Atlas checked Accessibility trust status"
        )
        return AXIsProcessTrusted() ? PrivacyPulseStatus.allowed : PrivacyPulseStatus.denied
    }

    private func status(from authorizationStatus: AVAuthorizationStatus) -> PrivacyPulseStatus {
        switch authorizationStatus {
        case .authorized:
            return .allowed
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }
}
