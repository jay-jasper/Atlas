import Foundation

protocol SystemCommandProcess: AnyObject {
    var isRunning: Bool { get }
    func terminate()
}

protocol SystemCommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult
    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess
}

enum SystemCommandRunnerError: Error, Equatable {
    case invalidOutput
}

final class LiveSystemCommandProcess: SystemCommandProcess {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        process.terminate()
    }
}

struct LiveSystemCommandRunner: SystemCommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        return SystemCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            standardError: String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        return LiveSystemCommandProcess(process: process)
    }
}
