import Foundation

/// Pure pomodoro state machine. Given a configuration and the running session
/// log, computes the current phase and time remaining. Deterministic and
/// independent of real timers, so it is fully unit-testable.
enum PomodoroPhase: String, Equatable {
    case focus
    case shortBreak
    case longBreak
    case idle
}

struct PomodoroConfig: Equatable {
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    /// Number of focus sessions before a long break.
    var sessionsBeforeLongBreak: Int

    static let `default` = PomodoroConfig(
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
        sessionsBeforeLongBreak: 4
    )
}

enum PomodoroEngine {
    /// The phase that follows `completedFocusSessions` focus sessions.
    static func phaseAfterFocus(completedFocusSessions: Int, config: PomodoroConfig) -> PomodoroPhase {
        guard config.sessionsBeforeLongBreak > 0 else { return .shortBreak }
        return completedFocusSessions % config.sessionsBeforeLongBreak == 0 ? .longBreak : .shortBreak
    }

    static func duration(for phase: PomodoroPhase, config: PomodoroConfig) -> Int {
        switch phase {
        case .focus: return config.focusMinutes * 60
        case .shortBreak: return config.shortBreakMinutes * 60
        case .longBreak: return config.longBreakMinutes * 60
        case .idle: return 0
        }
    }

    /// Remaining seconds for a phase started `elapsed` seconds ago.
    static func remaining(phase: PomodoroPhase, elapsed: TimeInterval, config: PomodoroConfig) -> Int {
        max(0, duration(for: phase, config: config) - Int(elapsed))
    }

    static func isComplete(phase: PomodoroPhase, elapsed: TimeInterval, config: PomodoroConfig) -> Bool {
        remaining(phase: phase, elapsed: elapsed, config: config) == 0 && phase != .idle
    }

    static func format(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
