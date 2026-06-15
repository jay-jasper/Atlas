import XCTest
@testable import Atlas

@MainActor
final class BatteryHealthFormatterTests: XCTestCase {
    func testConditionThresholds() {
        XCTAssertEqual(BatteryHealthFormatter.condition(healthPercent: 95), .normal)
        XCTAssertEqual(BatteryHealthFormatter.condition(healthPercent: 80), .normal)
        XCTAssertEqual(BatteryHealthFormatter.condition(healthPercent: 75), .serviceRecommended)
        XCTAssertEqual(BatteryHealthFormatter.condition(healthPercent: 55), .replaceSoon)
    }

    func testFormatTime() {
        XCTAssertEqual(BatteryHealthFormatter.formatTime(seconds: 8100), "2h 15m")
        XCTAssertEqual(BatteryHealthFormatter.formatTime(seconds: 600), "10m")
        XCTAssertNil(BatteryHealthFormatter.formatTime(seconds: 0))
        XCTAssertNil(BatteryHealthFormatter.formatTime(seconds: nil))
    }

    func testFormatHealthAndCycles() {
        XCTAssertEqual(BatteryHealthFormatter.formatHealth(88.6), "89%")
        XCTAssertEqual(BatteryHealthFormatter.formatCycles(123), "123 cycles")
        XCTAssertEqual(BatteryHealthFormatter.formatCycles(nil), "—")
    }
}

@MainActor
final class BatteryHealthServiceTests: XCTestCase {
    func testReadsInjectedSnapshot() {
        let snap = MonitoringBatterySnapshot(
            chargePercent: 80, isCharging: true,
            timeToEmptySecs: nil, timeToFullSecs: 1200,
            healthPercent: 92, cycleCount: 50
        )
        let service = BatteryHealthService(read: { snap })
        XCTAssertTrue(service.hasBattery)
        XCTAssertEqual(service.snapshot?.healthPercent, 92)
    }

    func testNoBattery() {
        let service = BatteryHealthService(read: { nil })
        XCTAssertFalse(service.hasBattery)
        XCTAssertNil(service.snapshot)
    }
}
