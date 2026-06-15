import XCTest
@testable import Atlas

@MainActor
final class PomodoroEngineTests: XCTestCase {
    private let config = PomodoroConfig.default

    func testDurations() {
        XCTAssertEqual(PomodoroEngine.duration(for: .focus, config: config), 25 * 60)
        XCTAssertEqual(PomodoroEngine.duration(for: .shortBreak, config: config), 5 * 60)
        XCTAssertEqual(PomodoroEngine.duration(for: .longBreak, config: config), 15 * 60)
    }

    func testLongBreakEveryFourthSession() {
        XCTAssertEqual(PomodoroEngine.phaseAfterFocus(completedFocusSessions: 1, config: config), .shortBreak)
        XCTAssertEqual(PomodoroEngine.phaseAfterFocus(completedFocusSessions: 3, config: config), .shortBreak)
        XCTAssertEqual(PomodoroEngine.phaseAfterFocus(completedFocusSessions: 4, config: config), .longBreak)
        XCTAssertEqual(PomodoroEngine.phaseAfterFocus(completedFocusSessions: 8, config: config), .longBreak)
    }

    func testRemainingAndCompletion() {
        XCTAssertEqual(PomodoroEngine.remaining(phase: .focus, elapsed: 60, config: config), 24 * 60)
        XCTAssertFalse(PomodoroEngine.isComplete(phase: .focus, elapsed: 60, config: config))
        XCTAssertTrue(PomodoroEngine.isComplete(phase: .focus, elapsed: 25 * 60, config: config))
    }

    func testFormat() {
        XCTAssertEqual(PomodoroEngine.format(seconds: 65), "01:05")
        XCTAssertEqual(PomodoroEngine.format(seconds: 0), "00:00")
        XCTAssertEqual(PomodoroEngine.format(seconds: -10), "00:00")
    }
}

@MainActor
final class PomodoroServiceTests: XCTestCase {
    func testStartFocusFiresSceneHook() {
        var focusStarts = 0
        var current = Date(timeIntervalSince1970: 0)
        let service = PomodoroService(now: { current })
        service.onFocusStarted = { focusStarts += 1 }

        service.startFocus()
        XCTAssertEqual(service.phase, .focus)
        XCTAssertTrue(service.isRunning)
        XCTAssertEqual(focusStarts, 1)
        XCTAssertEqual(service.remainingSeconds, 25 * 60)

        // Advance to completion -> moves to short break, increments count.
        current = Date(timeIntervalSince1970: 25 * 60)
        service.tick(at: current)
        XCTAssertEqual(service.completedFocusSessions, 1)
        XCTAssertEqual(service.phase, .shortBreak)
    }

    func testSkipAdvancesPhase() {
        let service = PomodoroService(now: { Date(timeIntervalSince1970: 0) })
        service.startFocus()
        service.skip()
        XCTAssertEqual(service.completedFocusSessions, 1)
        XCTAssertEqual(service.phase, .shortBreak)
    }

    func testResetReturnsToIdle() {
        let service = PomodoroService(now: { Date(timeIntervalSince1970: 0) })
        service.startFocus()
        service.reset()
        XCTAssertEqual(service.phase, .idle)
        XCTAssertFalse(service.isRunning)
    }
}
