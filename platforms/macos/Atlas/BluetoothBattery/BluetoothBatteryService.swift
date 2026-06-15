import Foundation

@MainActor
final class BluetoothBatteryService: ObservableObject {
    @Published private(set) var devices: [BluetoothDeviceBattery] = []
    @Published private(set) var statusMessage = ""

    private let runner: SystemCommandRunning

    init(runner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.runner = runner
        refresh()
    }

    func refresh() {
        guard let result = try? runner.run(
            "/usr/sbin/ioreg",
            arguments: ["-r", "-l", "-k", "BatteryPercent"]
        ), result.succeeded else {
            statusMessage = "Could not read Bluetooth battery info."
            devices = []
            return
        }
        devices = BluetoothBatteryParser.parse(result.standardOutput)
        statusMessage = devices.isEmpty ? "No Bluetooth devices reporting battery." : ""
    }
}
