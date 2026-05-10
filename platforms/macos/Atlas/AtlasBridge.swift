import AppKit
import CoreGraphics
import Foundation

class AtlasBridge {
    static var monitoringTimer: Timer?
    static var captureService: AtlasCaptureService = .live
    static var windowCaptureProvider: WindowCaptureProviding = CoreGraphicsWindowCaptureProvider()

    static func listFeatures() -> [String] {
        return AtlasModule.allCases.map(\.featureName)
    }

    static func toggleFeature(name: String, enabled: Bool) {
        print("Feature \(name) toggled to \(enabled)")
    }

    static func startMonitoring(callback: @escaping (MonitoringSystemSnapshot) -> Void) {
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let coreCount = 10
            let cores = (0..<coreCount).map { i in
                MonitoringCpuCoreSnapshot(name: "cpu\(i)", usage: Float.random(in: 5...95), frequencyMhz: UInt64.random(in: 2400...3600))
            }
            let processes = (0..<5).map { i in
                MonitoringProcessSnapshot(
                    pid: UInt32(1000 + i),
                    name: ["Xcode", "Safari", "Slack", "Terminal", "Finder"][i],
                    cpuUsage: Float.random(in: 0...40),
                    memBytes: UInt64.random(in: 50_000_000...500_000_000)
                )
            }
            let interfaces = [
                MonitoringNetworkInterfaceSnapshot(name: "en0", uploadBps: UInt64.random(in: 0...500_000), downloadBps: UInt64.random(in: 0...2_000_000)),
                MonitoringNetworkInterfaceSnapshot(name: "en1", uploadBps: 0, downloadBps: 0),
            ]
            let disks = [
                MonitoringDiskSnapshot(name: "Macintosh HD", mountPoint: "/", totalBytes: 500_000_000_000, usedBytes: 250_000_000_000, availableBytes: 250_000_000_000),
                MonitoringDiskSnapshot(name: "Data", mountPoint: "/System/Volumes/Data", totalBytes: 500_000_000_000, usedBytes: 300_000_000_000, availableBytes: 200_000_000_000),
            ]
            let battery = MonitoringBatterySnapshot(
                chargePercent: 78.0, isCharging: false,
                timeToEmptySecs: 7200, timeToFullSecs: nil,
                healthPercent: 95.0, cycleCount: 143
            )
            let temps = [
                MonitoringTemperatureSnapshot(label: "CPU Core 1", celsius: 55.0),
                MonitoringTemperatureSnapshot(label: "CPU Core 2", celsius: 57.0),
                MonitoringTemperatureSnapshot(label: "GPU", celsius: 48.0),
            ]
            callback(MonitoringSystemSnapshot(
                cpuUsage: cores.map(\.usage).reduce(0, +) / Float(cores.count),
                memUsedBytes: 8_500_000_000, memTotalBytes: 16_000_000_000,
                netUploadBps: interfaces.map(\.uploadBps).reduce(0, +),
                netDownloadBps: interfaces.map(\.downloadBps).reduce(0, +),
                cpuCores: cores,
                memFreeBytes: 1_500_000_000, memAvailableBytes: 4_000_000_000,
                swapUsedBytes: 512_000_000, swapTotalBytes: 2_048_000_000,
                topCpuProcesses: processes.sorted { $0.cpuUsage > $1.cpuUsage },
                topMemProcesses: processes.sorted { $0.memBytes > $1.memBytes },
                networkInterfaces: interfaces, disks: disks,
                battery: battery, temperatures: temps
            ))
        }
    }

    static func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    static func killPortProcess(pid: UInt32) -> Bool {
        print("Killing process \(pid)")
        return true
    }

    static func captureRegion(x: Int32, y: Int32, width: UInt32, height: UInt32) throws -> Data {
        try captureService.captureRegion(x, y, width, height)
    }

    static func captureFullScreen() throws -> Data {
        try captureService.captureFullScreen()
    }

    static func listCapturableWindows() throws -> [CapturableWindow] {
        try windowCaptureProvider.listWindows()
    }

    static func captureWindow(id: CGWindowID) throws -> Data {
        try windowCaptureProvider.captureWindow(id: id)
    }
}
