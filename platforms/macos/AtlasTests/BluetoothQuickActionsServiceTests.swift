import XCTest
@testable import Atlas

final class BluetoothQuickActionsServiceTests: XCTestCase {
    private let service = BluetoothQuickActionsService()

    func testParseEmptyOutputReturnsEmptyList() {
        XCTAssertEqual(service.parseSystemProfiler("").count, 0)
    }

    func testParseSingleConnectedDevice() {
        let output = """
            AirPods Pro:
              Address: 11:22:33:44:55:66
              Connected: Yes
        """
        let devices = service.parseSystemProfiler(output)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].name, "AirPods Pro")
        XCTAssertEqual(devices[0].address, "11:22:33:44:55:66")
        XCTAssertTrue(devices[0].isConnected)
    }

    func testParseDisconnectedDevice() {
        let output = """
            Magic Keyboard:
              Address: AA:BB:CC:DD:EE:FF
              Connected: No
        """
        let devices = service.parseSystemProfiler(output)
        XCTAssertEqual(devices.count, 1)
        XCTAssertFalse(devices[0].isConnected)
    }

    func testParseMultipleDevices() {
        let output = """
            AirPods Pro:
              Address: 11:22:33:44:55:66
              Connected: Yes
            Magic Mouse:
              Address: AA:BB:CC:DD:EE:FF
              Connected: No
        """
        let devices = service.parseSystemProfiler(output)
        XCTAssertEqual(devices.count, 2)
    }

    func testConnectedDeviceNamesReturnsOnlyConnected() {
        let output = """
            AirPods Pro:
              Address: 11:22:33:44:55:66
              Connected: Yes
            Magic Mouse:
              Address: AA:BB:CC:DD:EE:FF
              Connected: No
        """
        let devices = service.parseSystemProfiler(output)
        let connected = devices.filter(\.isConnected).map(\.name)
        XCTAssertEqual(connected, ["AirPods Pro"])
    }

    func testParseIgnoresBluetoothSectionHeaders() {
        let output = """
            Bluetooth:
              AirPods:
                Address: 11:22:33:44:55:66
                Connected: Yes
        """
        let devices = service.parseSystemProfiler(output)
        XCTAssertFalse(devices.contains { $0.name == "Bluetooth" })
    }
}
