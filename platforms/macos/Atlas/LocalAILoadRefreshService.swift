import Foundation

protocol LocalAILoadCollecting {
    func snapshot() throws -> LocalAILoadSnapshot
}

extension LocalAILoadMonitor: LocalAILoadCollecting {
    func snapshot() throws -> LocalAILoadSnapshot {
        try snapshot(now: Date())
    }
}

protocol LocalAILoadScheduling {
    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void)
    func cancel()
}

final class TimerLocalAILoadScheduler: LocalAILoadScheduling {
    private var timer: Timer?

    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in tick() }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

final class LocalAILoadRefreshService {
    private let collector: LocalAILoadCollecting
    private let scheduler: LocalAILoadScheduling
    private let interval: TimeInterval

    init(
        collector: LocalAILoadCollecting = LocalAILoadMonitor(),
        scheduler: LocalAILoadScheduling = TimerLocalAILoadScheduler(),
        interval: TimeInterval = 5
    ) {
        self.collector = collector
        self.scheduler = scheduler
        self.interval = interval
    }

    func start(onSnapshot: @escaping (LocalAILoadSnapshot) -> Void) {
        refresh(onSnapshot: onSnapshot)
        scheduler.schedule(every: interval) { [weak self] in
            self?.refresh(onSnapshot: onSnapshot)
        }
    }

    func stop() {
        scheduler.cancel()
    }

    private func refresh(onSnapshot: (LocalAILoadSnapshot) -> Void) {
        if let snapshot = try? collector.snapshot() {
            onSnapshot(snapshot)
        }
    }
}
