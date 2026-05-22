import XCTest
@testable import Atlas

@MainActor
final class HandMirrorServiceTests: XCTestCase {
    func testAuthorizedPermissionCanOpenMirror() async {
        let permissions = FakeCameraPermissionProvider(state: .authorized)
        let service = HandMirrorService(permissionProvider: permissions)

        let allowed = await service.prepareForPreview()

        XCTAssertTrue(allowed)
        XCTAssertEqual(service.permissionState, .authorized)
    }

    func testDeniedPermissionDoesNotOpenMirror() async {
        let permissions = FakeCameraPermissionProvider(state: .denied)
        let service = HandMirrorService(permissionProvider: permissions)

        let allowed = await service.prepareForPreview()

        XCTAssertFalse(allowed)
        XCTAssertEqual(service.permissionState, .denied)
    }

    func testNotDeterminedRequestsPermission() async {
        let permissions = FakeCameraPermissionProvider(state: .notDetermined, requestResult: true)
        let service = HandMirrorService(permissionProvider: permissions)

        let allowed = await service.prepareForPreview()

        XCTAssertTrue(allowed)
        XCTAssertEqual(permissions.requestCallCount, 1)
        XCTAssertEqual(service.permissionState, .authorized)
    }
}

final class FakeCameraPermissionProvider: CameraPermissionProviding {
    private var state: CameraPermissionState
    private let requestResult: Bool
    private(set) var requestCallCount = 0

    init(state: CameraPermissionState, requestResult: Bool = false) {
        self.state = state
        self.requestResult = requestResult
    }

    func currentState() -> CameraPermissionState {
        state
    }

    func requestAccess() async -> Bool {
        requestCallCount += 1
        state = requestResult ? .authorized : .denied
        return requestResult
    }
}
