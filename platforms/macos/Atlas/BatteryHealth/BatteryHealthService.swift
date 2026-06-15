import Foundation

@MainActor
final class BatteryHealthService: ObservableObject {
    @Published private(set) var snapshot: MonitoringBatterySnapshot?
    @Published private(set) var hasBattery = true

    /// Reads a one-shot battery snapshot. Injected for testing; the live
    /// implementation calls the Rust core via FFI.
    private let read: () -> MonitoringBatterySnapshot?

    init(read: @escaping () -> MonitoringBatterySnapshot? = BatteryHealthService.liveRead) {
        self.read = read
        refresh()
    }

    func refresh() {
        let value = read()
        snapshot = value
        hasBattery = value != nil
    }

    static func liveRead() -> MonitoringBatterySnapshot? {
        guard let b = Atlas.currentBattery() else { return nil }
        return MonitoringBatterySnapshot(
            chargePercent: b.chargePercent,
            isCharging: b.isCharging,
            timeToEmptySecs: b.timeToEmptySecs,
            timeToFullSecs: b.timeToFullSecs,
            healthPercent: b.healthPercent,
            cycleCount: b.cycleCount
        )
    }
}
