import XCTest
@testable import Atlas

final class MonitoringServiceTests: XCTestCase {
    func testStartMonitoringReceivesCallbackAndPassesSnapshotThrough() throws {
        let expected = MonitoringSystemSnapshot.testFixture()
        var received: MonitoringSystemSnapshot?
        var didReceiveCallback = false
        let service = MonitoringService(
            startMonitoring: { callback in
                didReceiveCallback = true
                callback(expected)
            },
            stopMonitoring: {},
            lookupPort: { _ in nil },
            killPortProcess: { _ in false }
        )

        try service.startMonitoring(callback: { snapshot in
            received = snapshot
        })

        XCTAssertTrue(didReceiveCallback)
        XCTAssertEqual(received, expected)
    }

    func testLookupPortAndKillPortProcessDelegateArgumentsAndReturnValues() throws {
        let expectedPort = MonitoringPortProcess(port: 3000, pid: 42, processName: "node")
        var lookupPortArgument: UInt16?
        var killPidArgument: UInt32?
        let service = MonitoringService(
            startMonitoring: { _ in },
            stopMonitoring: {},
            lookupPort: { port in
                lookupPortArgument = port
                return expectedPort
            },
            killPortProcess: { pid in
                killPidArgument = pid
                return true
            }
        )

        let port = try service.lookupPort(3000)
        let killed = try service.killPortProcess(42)

        XCTAssertEqual(lookupPortArgument, 3000)
        XCTAssertEqual(port, expectedPort)
        XCTAssertEqual(killPidArgument, 42)
        XCTAssertTrue(killed)
    }

    func testStartMonitoringPropagatesInjectedError() {
        let service = MonitoringService(
            startMonitoring: { _ in throw MonitoringServiceTestError.denied },
            stopMonitoring: {},
            lookupPort: { _ in nil },
            killPortProcess: { _ in false }
        )

        XCTAssertThrowsError(try service.startMonitoring(callback: { _ in })) { error in
            XCTAssertEqual(error.localizedDescription, "denied")
        }
    }
}

private enum MonitoringServiceTestError: LocalizedError {
    case denied

    var errorDescription: String? {
        switch self {
        case .denied:
            return "denied"
        }
    }
}

private extension MonitoringSystemSnapshot {
    static func testFixture() -> MonitoringSystemSnapshot {
        MonitoringSystemSnapshot(
            cpuUsage: 42.5,
            memUsedBytes: 6_000,
            memTotalBytes: 10_000,
            netUploadBps: 100,
            netDownloadBps: 200,
            cpuCores: [
                MonitoringCpuCoreSnapshot(name: "cpu0", usage: 10.5, frequencyMhz: 3_200)
            ],
            memFreeBytes: 1_000,
            memAvailableBytes: 3_000,
            swapUsedBytes: 128,
            swapTotalBytes: 256,
            topCpuProcesses: [
                MonitoringProcessSnapshot(pid: 11, name: "CPU", cpuUsage: 21.5, memBytes: 900)
            ],
            topMemProcesses: [
                MonitoringProcessSnapshot(pid: 12, name: "MEM", cpuUsage: 2.5, memBytes: 1_200)
            ],
            networkInterfaces: [
                MonitoringNetworkInterfaceSnapshot(name: "en0", uploadBps: 10, downloadBps: 20)
            ],
            disks: [
                MonitoringDiskSnapshot(name: "Macintosh HD", mountPoint: "/", totalBytes: 100, usedBytes: 40, availableBytes: 60)
            ],
            battery: MonitoringBatterySnapshot(
                chargePercent: 77,
                isCharging: true,
                timeToEmptySecs: nil,
                timeToFullSecs: 1_200,
                healthPercent: 95,
                cycleCount: 123
            ),
            temperatures: [
                MonitoringTemperatureSnapshot(label: "CPU", celsius: 55)
            ]
        )
    }
}
