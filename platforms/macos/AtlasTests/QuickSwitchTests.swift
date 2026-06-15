import XCTest
@testable import Atlas

@MainActor
final class QuickSwitchCommandBuilderTests: XCTestCase {
    func testDarkModeUsesOsascript() {
        let cmd = QuickSwitchCommandBuilder.setCommand(.darkMode, on: true)
        XCTAssertEqual(cmd.executable, "/usr/bin/osascript")
        XCTAssertTrue(cmd.arguments.last?.contains("set dark mode to true") ?? false)
    }

    func testBluetoothUsesBlueutil() {
        XCTAssertEqual(
            QuickSwitchCommandBuilder.setCommand(.bluetooth, on: false).arguments,
            ["--power", "0"]
        )
    }

    func testDoNotDisturbUsesShortcuts() {
        let cmd = QuickSwitchCommandBuilder.setCommand(.doNotDisturb, on: true)
        XCTAssertEqual(cmd.executable, "/usr/bin/shortcuts")
        XCTAssertEqual(cmd.arguments.first, "run")
    }
}

private final class RecordingRunner: SystemCommandRunning {
    private(set) var ran: [(String, [String])] = []
    var shouldThrow = false
    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        if shouldThrow { throw NSError(domain: "t", code: 1) }
        ran.append((executable, arguments))
        return SystemCommandResult(terminationStatus: 0, standardOutput: "", standardError: "")
    }
    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess { QSStub() }
}
private final class QSStub: SystemCommandProcess { var isRunning = false; func terminate() {} }

@MainActor
final class QuickSwitchServiceTests: XCTestCase {
    func testToggleRunsCommandAndUpdatesState() {
        let runner = RecordingRunner()
        let service = QuickSwitchService(runner: runner)
        XCTAssertFalse(service.isOn(.darkMode))
        service.toggle(.darkMode)
        XCTAssertTrue(service.isOn(.darkMode))
        XCTAssertEqual(runner.ran.first?.0, "/usr/bin/osascript")
    }

    func testKeepAwakeUsesInProcessHook() {
        let runner = RecordingRunner()
        let service = QuickSwitchService(runner: runner)
        var hookValues: [Bool] = []
        service.onKeepAwakeChanged = { hookValues.append($0) }
        service.set(.keepAwake, on: true)
        XCTAssertEqual(hookValues, [true])
        XCTAssertTrue(service.isOn(.keepAwake))
        XCTAssertTrue(runner.ran.isEmpty) // not shelled out
    }

    func testFailureSetsStatusAndKeepsStateOff() {
        let runner = RecordingRunner()
        runner.shouldThrow = true
        let service = QuickSwitchService(runner: runner)
        service.toggle(.bluetooth)
        XCTAssertFalse(service.isOn(.bluetooth))
        XCTAssertFalse(service.statusMessage.isEmpty)
    }
}
