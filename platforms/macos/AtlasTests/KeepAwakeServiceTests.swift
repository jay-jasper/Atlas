import XCTest
@testable import Atlas

@MainActor
final class KeepAwakeServiceTests: XCTestCase {
    func testStartLaunchesCaffeinateOnce() throws {
        let runner = FakeSystemCommandRunner()
        let service = KeepAwakeService(commandRunner: runner)

        try service.start()
        try service.start()

        XCTAssertEqual(runner.startedCommands, [
            FakeSystemCommandRunner.StartedCommand(executable: "/usr/bin/caffeinate", arguments: ["-dimsu"])
        ])
        XCTAssertEqual(service.status, .running)
    }

    func testStopTerminatesRunningProcess() throws {
        let runner = FakeSystemCommandRunner()
        let service = KeepAwakeService(commandRunner: runner)

        try service.start()
        service.stop()

        XCTAssertEqual(runner.processes.first?.terminateCallCount, 1)
        XCTAssertEqual(service.status, .idle)
    }

    func testStartFailureSetsFailedStatus() {
        let runner = FakeSystemCommandRunner(startError: NSError(domain: "test", code: 1))
        let service = KeepAwakeService(commandRunner: runner)

        XCTAssertThrowsError(try service.start())
        guard case .failed(let message) = service.status else {
            return XCTFail("Expected failed status")
        }
        XCTAssertTrue(message.contains("test error 1"))
    }

    func testCommandRunnerDrainsAndCapsLargeOutput() throws {
        let runner = LiveSystemCommandRunner(timeout: 2, outputLimit: 1_024)

        let result = try runner.run(
            "/bin/sh",
            arguments: ["-c", "yes x | head -c 200000"]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertLessThanOrEqual(result.standardOutput.utf8.count, 1_044)
        XCTAssertTrue(result.standardOutput.hasSuffix("[output truncated]"))
    }

    func testCommandRunnerTerminatesTimedOutProcess() {
        let runner = LiveSystemCommandRunner(timeout: 0.05)

        XCTAssertThrowsError(try runner.run("/bin/sleep", arguments: ["5"])) { error in
            XCTAssertEqual(error as? SystemCommandRunnerError, .timedOut(seconds: 0.05))
        }
    }
}

final class FakeSystemCommandProcess: SystemCommandProcess {
    var isRunning = true
    private(set) var terminateCallCount = 0

    func terminate() {
        terminateCallCount += 1
        isRunning = false
    }
}

final class FakeSystemCommandRunner: SystemCommandRunning {
    struct StartedCommand: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let startError: Error?
    private(set) var startedCommands: [StartedCommand] = []
    private(set) var processes: [FakeSystemCommandProcess] = []

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        SystemCommandResult(terminationStatus: 0, standardOutput: "", standardError: "")
    }

    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
        if let startError {
            throw startError
        }
        startedCommands.append(StartedCommand(executable: executable, arguments: arguments))
        let process = FakeSystemCommandProcess()
        processes.append(process)
        return process
    }
}
