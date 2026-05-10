import AppKit
import Foundation

private extension NSImage {
    static func atlasMockScreenshot(width: Int, height: Int) -> Data {
        let size = NSSize(width: max(1, width), height: max(1, height))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: NSRect(x: 4, y: 4, width: size.width - 8, height: size.height - 8))
        border.lineWidth = 4
        border.stroke()
        NSString(string: "\(Int(size.width)) x \(Int(size.height))").draw(
            at: NSPoint(x: 12, y: max(12, size.height / 2 - 8)),
            withAttributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
            ]
        )
        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        }

        return png
    }
}

class AtlasBridge {
    static var monitoringTimer: Timer?

    static func listFeatures() -> [String] {
        return AtlasModule.allCases.map(\.featureName)
    }

    static func toggleFeature(name: String, enabled: Bool) {
        print("Feature \(name) toggled to \(enabled)")
    }

    static func startMonitoring(callback: @escaping (SystemSnapshot) -> Void) {
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let coreCount = 10
            let cores = (0..<coreCount).map { i in
                CpuCoreSnapshot(name: "cpu\(i)", usage: Float.random(in: 5...95), frequencyMhz: UInt64.random(in: 2400...3600))
            }
            let processes = (0..<5).map { i in
                ProcessSnapshot(
                    pid: UInt32(1000 + i),
                    name: ["Xcode", "Safari", "Slack", "Terminal", "Finder"][i],
                    cpuUsage: Float.random(in: 0...40),
                    memBytes: UInt64.random(in: 50_000_000...500_000_000)
                )
            }
            let interfaces = [
                NetworkInterfaceSnapshot(name: "en0", uploadBps: UInt64.random(in: 0...500_000), downloadBps: UInt64.random(in: 0...2_000_000)),
                NetworkInterfaceSnapshot(name: "en1", uploadBps: 0, downloadBps: 0),
            ]
            let disks = [
                DiskSnapshot(name: "Macintosh HD", mountPoint: "/", totalBytes: 500_000_000_000, usedBytes: 250_000_000_000, availableBytes: 250_000_000_000),
                DiskSnapshot(name: "Data", mountPoint: "/System/Volumes/Data", totalBytes: 500_000_000_000, usedBytes: 300_000_000_000, availableBytes: 200_000_000_000),
            ]
            let battery = BatterySnapshot(
                chargePercent: 78.0, isCharging: false,
                timeToEmptySecs: 7200, timeToFullSecs: nil,
                healthPercent: 95.0, cycleCount: 143
            )
            let temps = [
                TemperatureSnapshot(label: "CPU Core 1", celsius: 55.0),
                TemperatureSnapshot(label: "CPU Core 2", celsius: 57.0),
                TemperatureSnapshot(label: "GPU", celsius: 48.0),
            ]
            callback(SystemSnapshot(
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

    static func captureRegion(x: Int32, y: Int32, width: UInt32, height: UInt32) -> Data? {
        print("Capturing region: x=\(x), y=\(y), width=\(width), height=\(height)")
        return NSImage.atlasMockScreenshot(width: Int(width), height: Int(height))
    }

    static func captureFullScreen() -> Data? {
        return NSImage.atlasMockScreenshot(width: 1440, height: 900)
    }
}
