import Foundation
import Darwin

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
    case timedOut(seconds: TimeInterval)
}

private final class CappedCommandOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var wasTruncated = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.availableData
            guard !chunk.isEmpty else { break }

            lock.lock()
            let remaining = max(0, limit - data.count)
            if remaining > 0 {
                data.append(chunk.prefix(remaining))
            }
            if chunk.count > remaining {
                wasTruncated = true
            }
            lock.unlock()
        }
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        let value = String(decoding: data, as: UTF8.self)
        return wasTruncated ? value + "\n[output truncated]" : value
    }
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
    private let timeout: TimeInterval
    private let outputLimit: Int

    init(timeout: TimeInterval = 30, outputLimit: Int = 1_048_576) {
        self.timeout = max(0.01, timeout)
        self.outputLimit = max(0, outputLimit)
    }

    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let outputBuffer = CappedCommandOutput(limit: outputLimit)
        let errorBuffer = CappedCommandOutput(limit: outputLimit)
        let readers = DispatchGroup()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { _ in finished.signal() }

        try process.run()

        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBuffer.drain(output.fileHandleForReading)
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBuffer.drain(error.fileHandleForReading)
            readers.leave()
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            output.fileHandleForReading.closeFile()
            error.fileHandleForReading.closeFile()
            readers.wait()
            throw SystemCommandRunnerError.timedOut(seconds: timeout)
        }

        readers.wait()

        return SystemCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: outputBuffer.string(),
            standardError: errorBuffer.string()
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
