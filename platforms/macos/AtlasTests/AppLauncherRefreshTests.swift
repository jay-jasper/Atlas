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
