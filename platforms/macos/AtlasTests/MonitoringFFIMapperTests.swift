import XCTest
@testable import Atlas

@MainActor
final class MonitoringFFIMapperTests: XCTestCase {
    func testMapsSystemSnapshot() {
        let ffiSnapshot = SystemSnapshot(
            cpuUsage: 42.5,
            memUsedBytes: 6_000,
            memTotalBytes: 10_000,
            netUploadBps: 100,
            netDownloadBps: 200,
            cpuCores: [
                CpuCoreSnapshot(name: "cpu0", usage: 10.5, frequencyMhz: 3_200)
            ],
            memFreeBytes: 1_000,
            memAvailableBytes: 3_000,
            swapUsedBytes: 128,
            swapTotalBytes: 256,
            topCpuProcesses: [
                ProcessSnapshot(pid: 11, name: "CPU", cpuUsage: 21.5, memBytes: 900)
            ],
            topMemProcesses: [
                ProcessSnapshot(pid: 12, name: "MEM", cpuUsage: 2.5, memBytes: 1_200)
            ],
            networkInterfaces: [
                NetworkInterfaceSnapshot(name: "en0", uploadBps: 10, downloadBps: 20)
            ],
            disks: [
                DiskSnapshot(name: "Macintosh HD", mountPoint: "/", totalBytes: 100, usedBytes: 40, availableBytes: 60)
            ],
            battery: BatterySnapshot(
                chargePercent: 77,
                isCharging: true,
                timeToEmptySecs: nil,
                timeToFullSecs: 1_200,
                healthPercent: 95,
                cycleCount: 123
            ),
            temperatures: [
                TemperatureSnapshot(label: "CPU", celsius: 55)
            ]
        )

        let snapshot = MonitoringFFIMapper.map(snapshot: ffiSnapshot)

        XCTAssertEqual(snapshot.cpuUsage, 42.5)
        XCTAssertEqual(snapshot.memUsedBytes, 6_000)
        XCTAssertEqual(snapshot.memTotalBytes, 10_000)
        XCTAssertEqual(snapshot.netUploadBps, 100)
        XCTAssertEqual(snapshot.netDownloadBps, 200)
        XCTAssertEqual(snapshot.cpuCores, [
            MonitoringCpuCoreSnapshot(name: "cpu0", usage: 10.5, frequencyMhz: 3_200)
        ])
        XCTAssertEqual(snapshot.memFreeBytes, 1_000)
        XCTAssertEqual(snapshot.memAvailableBytes, 3_000)
        XCTAssertEqual(snapshot.swapUsedBytes, 128)
        XCTAssertEqual(snapshot.swapTotalBytes, 256)
        XCTAssertEqual(snapshot.topCpuProcesses, [
            MonitoringProcessSnapshot(pid: 11, name: "CPU", cpuUsage: 21.5, memBytes: 900)
        ])
        XCTAssertEqual(snapshot.topMemProcesses, [
            MonitoringProcessSnapshot(pid: 12, name: "MEM", cpuUsage: 2.5, memBytes: 1_200)
        ])
        XCTAssertEqual(snapshot.networkInterfaces, [
            MonitoringNetworkInterfaceSnapshot(name: "en0", uploadBps: 10, downloadBps: 20)
        ])
        XCTAssertEqual(snapshot.disks, [
            MonitoringDiskSnapshot(name: "Macintosh HD", mountPoint: "/", totalBytes: 100, usedBytes: 40, availableBytes: 60)
        ])
        XCTAssertEqual(snapshot.battery, MonitoringBatterySnapshot(
            chargePercent: 77,
            isCharging: true,
            timeToEmptySecs: nil,
            timeToFullSecs: 1_200,
            healthPercent: 95,
            cycleCount: 123
        ))
        XCTAssertEqual(snapshot.temperatures, [
            MonitoringTemperatureSnapshot(label: "CPU", celsius: 55)
        ])
    }

    func testMapsPortProcess() {
        let info = PortProcessInfo(port: 3000, pid: 42, processName: "node")

        let mapped = MonitoringFFIMapper.map(port: info)

        XCTAssertEqual(mapped, MonitoringPortProcess(port: 3000, pid: 42, processName: "node"))
    }
}
