import XCTest
@testable import Atlas

@MainActor
final class DisplayControlServiceTests: XCTestCase {
    func testDetectsDDCSupportFromProbeOutput() throws {
        let probe = FakeDisplayCapabilityProbe(result: SystemCommandResult(
            terminationStatus: 0,
            standardOutput: "Display 1: Built-in Retina\nDisplay 2: LG UltraFine DDC/CI supported\n",
            standardError: ""
        ))
        let service = DisplayControlService(probe: probe)

        let displays = try service.refreshDisplays()

        XCTAssertEqual(displays, [
            DisplayDevice(id: "display-1", name: "Built-in Retina", isBuiltin: true, supportsDDC: false, ddcIndex: 1),
            DisplayDevice(id: "display-2", name: "LG UltraFine", isBuiltin: false, supportsDDC: true, ddcIndex: 2),
        ])
    }

    func testUnavailableProbeReturnsEmptyList() {
        let probe = FakeDisplayCapabilityProbe(result: SystemCommandResult(
            terminationStatus: 127,
            standardOutput: "",
            standardError: "ddcctl not found"
        ))
        let service = DisplayControlService(probe: probe)

        XCTAssertThrowsError(try service.refreshDisplays())
        XCTAssertEqual(service.displays, [])
        XCTAssertEqual(service.status, .unavailable("ddcctl not found"))
    }
}

struct FakeDisplayCapabilityProbe: DisplayCapabilityProbing {
    let result: SystemCommandResult

    func probe() throws -> SystemCommandResult {
        result
    }
}
