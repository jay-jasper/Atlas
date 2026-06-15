import XCTest
@testable import Atlas

@MainActor
final class LocalAILoadRefreshServiceTests: XCTestCase {
    func testStartRefreshesImmediatelyAndOnScheduledTicks() throws {
        let scheduler = ManualLocalAILoadScheduler()
        let collector = CountingLocalAILoadCollector(snapshots: [
            LocalAILoadSnapshot(providers: [], capturedAt: Date(timeIntervalSince1970: 1)),
            LocalAILoadSnapshot(
                providers: [
                    LocalAIProviderLoad(
                        provider: .ollama,
                        processCount: 1,
                        cpuPercent: 2,
                        residentMemoryBytes: 3,
                        accelerator: .unavailable
                    ),
                ],
                capturedAt: Date(timeIntervalSince1970: 2)
            ),
        ])
        var received: [LocalAILoadSnapshot] = []
        let service = LocalAILoadRefreshService(collector: collector, scheduler: scheduler, interval: 5)

        service.start { received.append($0) }
        scheduler.fire()

        XCTAssertEqual(received.map(\.capturedAt), [
            Date(timeIntervalSince1970: 1),
            Date(timeIntervalSince1970: 2),
        ])
        XCTAssertEqual(scheduler.startedIntervals, [5])
    }

    func testStopCancelsScheduledRefreshes() throws {
        let scheduler = ManualLocalAILoadScheduler()
        let collector = CountingLocalAILoadCollector(snapshots: [.empty, .empty])
        var refreshCount = 0
        let service = LocalAILoadRefreshService(collector: collector, scheduler: scheduler, interval: 5)

        service.start { _ in refreshCount += 1 }
        service.stop()
        scheduler.fire()

        XCTAssertEqual(refreshCount, 1)
        XCTAssertTrue(scheduler.cancelled)
    }
}

final class ManualLocalAILoadScheduler: LocalAILoadScheduling {
    var tick: (() -> Void)?
    var startedIntervals: [TimeInterval] = []
    var cancelled = false

    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) {
        startedIntervals.append(interval)
        self.tick = tick
    }

    func cancel() {
        cancelled = true
        tick = nil
    }

    func fire() {
        tick?()
    }
}

final class CountingLocalAILoadCollector: LocalAILoadCollecting {
    var snapshots: [LocalAILoadSnapshot]

    init(snapshots: [LocalAILoadSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() throws -> LocalAILoadSnapshot {
        snapshots.removeFirst()
    }
}
