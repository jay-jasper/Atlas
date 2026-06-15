import Combine
import Foundation

@MainActor
final class PomodoroService: ObservableObject {
    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var completedFocusSessions: Int = 0
    @Published private(set) var isRunning: Bool = false

    var config: PomodoroConfig
    /// Invoked when a focus phase completes — lets Scene System enter a DND scene.
    var onFocusStarted: (() -> Void)?
    var onPhaseCompleted: ((PomodoroPhase) -> Void)?

    private var phaseStart: Date?
    private var timer: AnyCancellable?
    private let now: () -> Date

    init(config: PomodoroConfig = .default, now: @escaping () -> Date = Date.init) {
        self.config = config
        self.now = now
    }

    func startFocus() {
        begin(phase: .focus)
        onFocusStarted?()
    }

    func reset() {
        timer?.cancel()
        timer = nil
        phase = .idle
        phaseStart = nil
        remainingSeconds = 0
        isRunning = false
    }

    func skip() {
        guard phase != .idle else { return }
        complete(current: phase)
    }

    /// Advances the timer based on wall-clock; called every second by the view's
    /// tick or by tests directly.
    func tick(at date: Date? = nil) {
        guard isRunning, let start = phaseStart else { return }
        let elapsed = (date ?? now()).timeIntervalSince(start)
        remainingSeconds = PomodoroEngine.remaining(phase: phase, elapsed: elapsed, config: config)
        if PomodoroEngine.isComplete(phase: phase, elapsed: elapsed, config: config) {
            complete(current: phase)
        }
    }

    private func begin(phase newPhase: PomodoroPhase) {
        phase = newPhase
        phaseStart = now()
        remainingSeconds = PomodoroEngine.duration(for: newPhase, config: config)
        isRunning = newPhase != .idle
        startTimerIfNeeded()
    }

    private func complete(current: PomodoroPhase) {
        onPhaseCompleted?(current)
        if current == .focus {
            completedFocusSessions += 1
            begin(phase: PomodoroEngine.phaseAfterFocus(
                completedFocusSessions: completedFocusSessions,
                config: config
            ))
        } else {
            begin(phase: .focus)
            onFocusStarted?()
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }
}
