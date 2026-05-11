import XCTest
@testable import Atlas

private extension MonitoringProviding where Self == MonitoringService {
    static var live: MonitoringService { MonitoringService.live }
}

private final class FakeMonitoringProvider: MonitoringProviding {
    var startCount = 0
    var stopCount = 0
    var callbackSnapshot = MonitoringSystemSnapshot.testFixture()
    var lookedUpPort: UInt16?
    var killedPID: UInt32?
    var lookupResult: MonitoringPortProcess?
    var killResult = true

    func startMonitoring(callback: @escaping (MonitoringSystemSnapshot) -> Void) throws {
        startCount += 1
        callback(callbackSnapshot)
    }

    func stopMonitoring() throws {
        stopCount += 1
    }

    func lookupPort(_ port: UInt16) throws -> MonitoringPortProcess? {
        lookedUpPort = port
        return lookupResult
    }

    func killPortProcess(_ pid: UInt32) throws -> Bool {
        killedPID = pid
        return killResult
    }
}

final class AtlasBridgeMonitoringTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.monitoringService = .live
        super.tearDown()
    }

    func testStartMonitoringUsesProvider() throws {
        let provider = FakeMonitoringProvider()
        AtlasBridge.monitoringService = provider
        var received: MonitoringSystemSnapshot?

        try AtlasBridge.startMonitoring { snapshot in
            received = snapshot
        }

        XCTAssertEqual(provider.startCount, 1)
        XCTAssertEqual(received, provider.callbackSnapshot)
    }

    func testStopMonitoringUsesProvider() throws {
        let provider = FakeMonitoringProvider()
        AtlasBridge.monitoringService = provider

        try AtlasBridge.stopMonitoring()

        XCTAssertEqual(provider.stopCount, 1)
    }

    func testLookupAndKillUseProvider() throws {
        let provider = FakeMonitoringProvider()
        provider.lookupResult = MonitoringPortProcess(port: 3000, pid: 44, processName: "node")
        AtlasBridge.monitoringService = provider

        let lookup = try AtlasBridge.lookupPort(3000)
        let killed = try AtlasBridge.killPortProcess(pid: 44)

        XCTAssertEqual(provider.lookedUpPort, 3000)
        XCTAssertEqual(lookup, MonitoringPortProcess(port: 3000, pid: 44, processName: "node"))
        XCTAssertEqual(provider.killedPID, 44)
        XCTAssertTrue(killed)
    }
}

private extension MonitoringSystemSnapshot {
    static func testFixture() -> MonitoringSystemSnapshot {
        MonitoringSystemSnapshot(
            cpuUsage: 1,
            memUsedBytes: 2,
            memTotalBytes: 3,
            netUploadBps: 4,
            netDownloadBps: 5,
            cpuCores: [],
            memFreeBytes: 6,
            memAvailableBytes: 7,
            swapUsedBytes: 8,
            swapTotalBytes: 9,
            topCpuProcesses: [],
            topMemProcesses: [],
            networkInterfaces: [],
            disks: [],
            battery: nil,
            temperatures: []
        )
    }
}
