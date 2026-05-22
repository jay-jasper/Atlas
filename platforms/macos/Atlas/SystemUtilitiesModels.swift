import Foundation

enum SystemUtilityStatus: Equatable {
    case idle
    case running
    case unavailable(String)
    case failed(String)
}

struct SystemCommandResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool {
        terminationStatus == 0
    }
}

enum CameraPermissionState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

struct DisplayDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let isBuiltin: Bool
    let supportsDDC: Bool

    var capabilitySummary: String {
        supportsDDC ? "DDC/CI available" : "Brightness control unavailable"
    }
}

struct SystemUtilitiesState: Equatable {
    var keepAwake: SystemUtilityStatus
    var presentationMode: SystemUtilityStatus
    var cameraPermission: CameraPermissionState
    var displays: [DisplayDevice]

    static let initial = SystemUtilitiesState(
        keepAwake: .idle,
        presentationMode: .idle,
        cameraPermission: .notDetermined,
        displays: []
    )
}
