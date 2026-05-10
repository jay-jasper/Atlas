import AppKit
import Foundation

private extension NSImage {
    static func atlasMockScreenshot(width: Int, height: Int) -> Data? {
        let pixelWidth = max(1, width)
        let pixelHeight = max(1, height)

        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: .alphaNonpremultiplied,
                bytesPerRow: pixelWidth * 4,
                bitsPerPixel: 32
            ),
            let pixels = bitmap.bitmapData
        else {
            return nil
        }

        let borderWidth = min(4, max(1, min(pixelWidth, pixelHeight) / 4))

        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let offset = (y * bitmap.bytesPerRow) + (x * 4)
                let isBorder = x < borderWidth
                    || y < borderWidth
                    || x >= pixelWidth - borderWidth
                    || y >= pixelHeight - borderWidth
                let red = UInt8((x * 13 + y * 3 + pixelWidth) % 256)
                let green = UInt8((x * 5 + y * 17 + pixelHeight) % 256)
                let blue = UInt8((x * 7 + y * 11 + pixelWidth + pixelHeight) % 256)

                pixels[offset] = isBorder ? 32 : red
                pixels[offset + 1] = isBorder ? 96 : green
                pixels[offset + 2] = isBorder ? 192 : blue
                pixels[offset + 3] = 255
            }
        }

        guard
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
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

    static func captureRegion(x: Int32, y: Int32, width: UInt32, height: UInt32) -> Data? {
        print("Capturing region: x=\(x), y=\(y), width=\(width), height=\(height)")
        return NSImage.atlasMockScreenshot(width: Int(width), height: Int(height))
    }

    static func captureFullScreen() -> Data? {
        return NSImage.atlasMockScreenshot(width: 1440, height: 900)
    }
}
