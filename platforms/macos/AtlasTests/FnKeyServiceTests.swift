import XCTest
@testable import Atlas

final class FnKeyServiceTests: XCTestCase {
    func testReadModeReturnsNilOnFailure() {
        let controller = StubFnKeyController(readResult: nil, setResult: false)
        let service = FnKeyService(controller: controller)
        XCTAssertFalse(service.isAvailable)
        XCTAssertFalse(service.statusMessage.isEmpty)
    }

    func testReadModeSetsCurrentMode() {
        let controller = StubFnKeyController(readResult: .fnKeys, setResult: true)
        let service = FnKeyService(controller: controller)
        XCTAssertTrue(service.isAvailable)
        XCTAssertEqual(service.currentMode, .fnKeys)
    }

    func testSetModeUpdatesCurrentMode() {
        let controller = StubFnKeyController(readResult: .mediaKeys, setResult: true)
        let service = FnKeyService(controller: controller)
        service.setMode(.fnKeys)
        XCTAssertEqual(service.currentMode, .fnKeys)
        XCTAssertTrue(service.statusMessage.isEmpty)
    }

    func testSetModeFailureSetsErrorMessage() {
        let controller = StubFnKeyController(readResult: .mediaKeys, setResult: false)
        let service = FnKeyService(controller: controller)
        service.setMode(.fnKeys)
        XCTAssertFalse(service.statusMessage.isEmpty)
    }

    func testFnKeyModeLabelIsNonEmpty() {
        XCTAssertFalse(FnKeyMode.fnKeys.label.isEmpty)
        XCTAssertFalse(FnKeyMode.mediaKeys.label.isEmpty)
    }

    func testAllCasesCountIsTwo() {
        XCTAssertEqual(FnKeyMode.allCases.count, 2)
    }
}

private final class StubFnKeyController: FnKeyControlling {
    private let readResult: FnKeyMode?
    private let setResult: Bool

    init(readResult: FnKeyMode?, setResult: Bool) {
        self.readResult = readResult
        self.setResult = setResult
    }

    func readMode() -> FnKeyMode? { readResult }
    func setMode(_ mode: FnKeyMode) -> Bool { setResult }
}
