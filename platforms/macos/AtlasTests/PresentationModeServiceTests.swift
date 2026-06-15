import XCTest
@testable import Atlas

@MainActor
final class PresentationModeServiceTests: XCTestCase {
    func testStartKeepsAwakeAndRunsNotificationFocusToggle() throws {
        let runner = RecordingCommandRunner()
        let keepAwake = KeepAwakeService(commandRunner: runner)
        let service = PresentationModeService(commandRunner: runner, keepAwakeService: keepAwake)

        try service.start()

        XCTAssertEqual(runner.startedCommands, [
            RecordingCommandRunner.Command(executable: "/usr/bin/caffeinate", arguments: ["-dimsu"])
        ])
        XCTAssertEqual(runner.ranCommands, [
            RecordingCommandRunner.Command(executable: "/usr/bin/osascript", arguments: [
                "-e",
                "tell application \"System Events\" to tell process \"Control Center\" to key code 113 using {option down}"
            ])
        ])
        XCTAssertEqual(service.status, .running)
    }

    func testStopRunsNotificationFocusToggleAndStopsKeepAwake() throws {
        let runner = RecordingCommandRunner()
        let keepAwake = KeepAwakeService(commandRunner: runner)
        let service = PresentationModeService(commandRunner: runner, keepAwakeService: keepAwake)

        try service.start()
        service.stop()

        XCTAssertEqual(runner.processes.first?.terminateCallCount, 1)
        XCTAssertEqual(runner.ranCommands.last, RecordingCommandRunner.Command(executable: "/usr/bin/osascript", arguments: [
            "-e",
            "tell application \"System Events\" to tell process \"Control Center\" to key code 113 using {option down}"
        ]))
        XCTAssertEqual(service.status, .idle)
    }

    func testNotificationCommandFailureStopsKeepAwakeAndReportsFailure() {
        let runner = RecordingCommandRunner(runResult: SystemCommandResult(terminationStatus: 1, standardOutput: "", standardError: "not allowed"))
        let service = PresentationModeService(commandRunner: runner, keepAwakeService: KeepAwakeService(commandRunner: runner))

        XCTAssertThrowsError(try service.start())
        XCTAssertEqual(runner.processes.first?.terminateCallCount, 1)
        XCTAssertEqual(service.status, .failed("not allowed"))
    }
}

final class RecordingCommandRunner: SystemCommandRunning {
    struct Command: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let runResult: SystemCommandResult
    private(set) var ranCommands: [Command] = []
    private(set) var startedCommands: [Command] = []
    private(set) var processes: [FakeSystemCommandProcess] = []

    init(runResult: SystemCommandResult = SystemCommandResult(terminationStatus: 0, standardOutput: "", standardError: "")) {
        self.runResult = runResult
    }

    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        ranCommands.append(Command(executable: executable, arguments: arguments))
        return runResult
    }

    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
        startedCommands.append(Command(executable: executable, arguments: arguments))
        let process = FakeSystemCommandProcess()
        processes.append(process)
        return process
    }
}
