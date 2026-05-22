import XCTest
@testable import Atlas

final class AppLauncherRefreshTests: XCTestCase {
    func testProviderScansOnInitWhenScannerIsInjected() {
        let scanner = FakeApplicationScanner(scans: [
            [AppEntry(name: "Initial", url: url("Initial"))],
        ])
        let observer = FakeApplicationChangeObserver()

        let provider = AppLauncherProvider(scanner: scanner, changeObserver: observer)

        XCTAssertEqual(scanner.scanCount, 1)
        XCTAssertEqual(provider.results(for: "initial").map(\.title), ["Initial"])
    }

    func testRefreshApplicationsReplacesCachedApps() {
        let scanner = FakeApplicationScanner(scans: [
            [AppEntry(name: "Initial", url: url("Initial"))],
            [AppEntry(name: "Updated", url: url("Updated"))],
        ])
        let provider = AppLauncherProvider(scanner: scanner, changeObserver: FakeApplicationChangeObserver())

        provider.refreshApplications()

        XCTAssertTrue(provider.results(for: "initial").isEmpty)
        XCTAssertEqual(provider.results(for: "updated").map(\.title), ["Updated"])
    }

    func testChangeObserverTriggersRefresh() {
        let scanner = FakeApplicationScanner(scans: [
            [AppEntry(name: "Initial", url: url("Initial"))],
            [AppEntry(name: "Installed", url: url("Installed"))],
        ])
        let observer = FakeApplicationChangeObserver()
        let provider = AppLauncherProvider(scanner: scanner, changeObserver: observer)

        observer.triggerChange()

        XCTAssertEqual(scanner.scanCount, 2)
        XCTAssertEqual(provider.results(for: "installed").map(\.title), ["Installed"])
    }

    func testInjectedStaticAppsDoNotStartObserver() {
        let observer = FakeApplicationChangeObserver()
        let provider = AppLauncherProvider(
            apps: [AppEntry(name: "Static", url: url("Static"))],
            changeObserver: observer
        )

        XCTAssertFalse(observer.didStart)
        XCTAssertEqual(provider.results(for: "static").map(\.title), ["Static"])
    }

    func testRefreshApplicationsSerializesScannerExecution() {
        let scanner = ConcurrentApplicationScanner()
        let provider = AppLauncherProvider(scanner: scanner, changeObserver: FakeApplicationChangeObserver())
        let group = DispatchGroup()

        for _ in 0..<5 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                provider.refreshApplications()
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(scanner.maxConcurrentScanCount, 1)
    }

    func testScanningProviderStopsObserverOnDeinit() {
        let scanner = FakeApplicationScanner(scans: [
            [AppEntry(name: "Initial", url: url("Initial"))],
        ])
        let observer = FakeApplicationChangeObserver()
        var provider: AppLauncherProvider? = AppLauncherProvider(scanner: scanner, changeObserver: observer)

        XCTAssertNotNil(provider)
        XCTAssertTrue(observer.didStart)

        provider = nil

        XCTAssertTrue(observer.didStop)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Applications/\(name).app")
    }
}

private final class FakeApplicationScanner: ApplicationScanning {
    private let scans: [[AppEntry]]
    private(set) var scanCount = 0

    init(scans: [[AppEntry]]) {
        self.scans = scans
    }

    func scanApplications() -> [AppEntry] {
        let index = min(scanCount, scans.count - 1)
        scanCount += 1
        return scans[index]
    }
}

private final class FakeApplicationChangeObserver: ApplicationChangeObserving {
    private var handler: (() -> Void)?
    private(set) var didStart = false
    private(set) var didStop = false

    func setChangeHandler(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() {
        didStart = true
    }

    func stop() {
        didStop = true
    }

    func triggerChange() {
        handler?()
    }
}

private final class ConcurrentApplicationScanner: ApplicationScanning {
    private let lock = NSLock()
    private var activeScanCount = 0
    private(set) var maxConcurrentScanCount = 0

    func scanApplications() -> [AppEntry] {
        lock.lock()
        activeScanCount += 1
        maxConcurrentScanCount = max(maxConcurrentScanCount, activeScanCount)
        lock.unlock()

        usleep(10_000)

        lock.lock()
        activeScanCount -= 1
        lock.unlock()

        return [AppEntry(name: "Scanned", url: URL(fileURLWithPath: "/Applications/Scanned.app"))]
    }
}
