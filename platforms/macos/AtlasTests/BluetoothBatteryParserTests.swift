import XCTest
@testable import Atlas

@MainActor
final class BluetoothBatteryParserTests: XCTestCase {
    func testParsesProductAndPercent() {
        let output = """
          | |   "Product" = "AirPods Pro"
          | |   "BatteryPercent" = 80
          | |   "Product" = "Magic Mouse"
          | |   "BatteryPercent" = 45
        """
        let devices = BluetoothBatteryParser.parse(output)
        XCTAssertEqual(devices, [
            BluetoothDeviceBattery(name: "AirPods Pro", percent: 80),
            BluetoothDeviceBattery(name: "Magic Mouse", percent: 45),
        ])
    }

    func testIgnoresZeroPercent() {
        let output = """
        "Product" = "Disconnected Device"
        "BatteryPercent" = 0
        """
        XCTAssertTrue(BluetoothBatteryParser.parse(output).isEmpty)
    }

    func testFallsBackToGenericName() {
        let output = "\"BatteryPercent\" = 55"
        XCTAssertEqual(BluetoothBatteryParser.parse(output).first?.name, "Bluetooth Device")
    }

    func testClampsAbove100() {
        let output = "\"Product\" = \"X\"\n\"BatteryPercent\" = 120"
        XCTAssertEqual(BluetoothBatteryParser.parse(output).first?.percent, 100)
    }

    func testEmptyOutput() {
        XCTAssertTrue(BluetoothBatteryParser.parse("").isEmpty)
    }
}
