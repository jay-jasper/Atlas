import XCTest
@testable import Atlas

@MainActor
final class AutomationOutputViewTests: XCTestCase {
    func testConfirmationRequiredCommandDoesNotRunBeforeConfirmation() {
        let runner = FakeAutomationRunner()
        let model = AutomationOutputViewModel(command: command(requiresConfirmation: true), runner: runner)

        model.run()

        XCTAssertTrue(runner.executed.isEmpty)
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.result)
    }

    func testConfirmedCommandRunsExactlyOnce() async {
        let runner = FakeAutomationRunner()
        let model = AutomationOutputViewModel(command: command(requiresConfirmation: true), runner: runner)

        model.hasConfirmed = true
        model.run()
        await waitForResult(model)
        model.run()

        XCTAssertEqual(runner.executed, [model.command])
        XCTAssertEqual(model.result, runner.result)
        XCTAssertFalse(model.isRunning)
    }

    func testNoConfirmationCommandCanRunWhenConfirmedByCaller() async {
        let runner = FakeAutomationRunner()
        let model = AutomationOutputViewModel(command: command(requiresConfirmation: false), runner: runner)

        model.hasConfirmed = true
        model.run()
        await waitForResult(model)

        XCTAssertEqual(runner.executed, [model.command])
        XCTAssertEqual(model.result, runner.result)
    }

    func testDisplayTextReturnsStdoutForSuccess() {
        let result = AutomationProcessResult(
            exitCode: 0,
            standardOutput: " ok \n",
            standardError: "",
            didTimeOut: false,
            duration: 0.1
        )

        XCTAssertEqual(AutomationOutputFormatter.displayText(for: result), "ok")
    }

    func testDisplayTextReturnsStderrForFailure() {
        let result = AutomationProcessResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "\nfailed\n",
            didTimeOut: false,
            duration: 0.1
        )

        XCTAssertEqual(AutomationOutputFormatter.displayText(for: result), "failed")
    }

    func testStatusTextReturnsTimeoutStatus() {
        let result = AutomationProcessResult(
            exitCode: -9,
            standardOutput: "",
            standardError: "",
            didTimeOut: true,
            duration: 3
        )

        XCTAssertEqual(AutomationOutputFormatter.statusText(for: result, timeoutSeconds: 3), "Timed out after 3s")
    }

    private func command(requiresConfirmation: Bool) -> CustomAutomationCommand {
        CustomAutomationCommand(
            title: "Deploy",
            command: "echo deploy",
            kind: .shell,
            timeoutSeconds: 3,
            requiresConfirmation: requiresConfirmation
        )
    }

    private func waitForResult(_ model: AutomationOutputViewModel) async {
        for _ in 0..<20 where model.result == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class FakeAutomationRunner: AutomationProcessRunning {
    private(set) var executed: [CustomAutomationCommand] = []
    var result = AutomationProcessResult(
        exitCode: 0,
        standardOutput: "ok",
        standardError: "",
        didTimeOut: false,
        duration: 0.1
    )

    func run(_ command: CustomAutomationCommand) async -> AutomationProcessResult {
        executed.append(command)
        return result
    }
}
