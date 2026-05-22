import AVFoundation
import Foundation

protocol CameraPermissionProviding {
    func currentState() -> CameraPermissionState
    func requestAccess() async -> Bool
}

struct LiveCameraPermissionProvider: CameraPermissionProviding {
    func currentState() -> CameraPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

@MainActor
final class HandMirrorService: ObservableObject {
    @Published private(set) var permissionState: CameraPermissionState

    private let permissionProvider: CameraPermissionProviding

    init(permissionProvider: CameraPermissionProviding = LiveCameraPermissionProvider()) {
        self.permissionProvider = permissionProvider
        self.permissionState = permissionProvider.currentState()
    }

    func prepareForPreview() async -> Bool {
        permissionState = permissionProvider.currentState()

        switch permissionState {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await permissionProvider.requestAccess()
            permissionState = granted ? .authorized : .denied
            return granted
        case .denied, .restricted:
            return false
        }
    }
}
