import Darwin
import Foundation

struct AutomationProcessResult: Equatable, Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
    let didTimeOut: Bool
    let duration: TimeInterval
}

protocol AutomationProcessRunning {
    func run(_ command: CustomAutomationCommand) async -> AutomationProcessResult
}

final class SystemAutomationProcessRunner: AutomationProcessRunning {
    private let dateProvider: () -> Date
    private let pollInterval: TimeInterval = 0.05
    private let shutdownGracePeriod: TimeInterval = 0.5

    init(dateProvider: @escaping () -> Date = Date.init) {
        self.dateProvider = dateProvider
    }

    func run(_ command: CustomAutomationCommand) async -> AutomationProcessResult {
        let startedAt = dateProvider()
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputBuffer = LockedDataBuffer()
        let errorBuffer = LockedDataBuffer()

        switch command.kind {
        case .shell:
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command.command]
        case .python:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", command.command]
        }

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputBuffer.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorBuffer.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            return AutomationProcessResult(
                exitCode: -1,
                standardOutput: "",
                standardError: error.localizedDescription,
                didTimeOut: false,
                duration: dateProvider().timeIntervalSince(startedAt)
            )
        }

        let timedOut = await waitBounded(for: process, timeout: command.timeoutSeconds)
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()

        let stdout = String(data: outputBuffer.data(), encoding: .utf8) ?? ""
        let stderr = String(data: errorBuffer.data(), encoding: .utf8) ?? ""

        return AutomationProcessResult(
            exitCode: timedOut ? -9 : process.terminationStatus,
            standardOutput: stdout,
            standardError: stderr,
            didTimeOut: timedOut,
            duration: dateProvider().timeIntervalSince(startedAt)
        )
    }

    private func waitBounded(for process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(max(timeout, 0.1))
        while process.isRunning && Date() < deadline {
            await sleepPollInterval()
        }
        guard process.isRunning else { return false }

        process.terminate()
        let terminateDeadline = Date().addingTimeInterval(shutdownGracePeriod)
        while process.isRunning && Date() < terminateDeadline {
            await sleepPollInterval()
        }
        guard process.isRunning else { return true }

        process.interrupt()
        let interruptDeadline = Date().addingTimeInterval(shutdownGracePeriod)
        while process.isRunning && Date() < interruptDeadline {
            await sleepPollInterval()
        }
        guard process.isRunning else { return true }

        kill(process.processIdentifier, SIGKILL)
        let killDeadline = Date().addingTimeInterval(shutdownGracePeriod)
        while process.isRunning && Date() < killDeadline {
            await sleepPollInterval()
        }

        return true
    }

    private func sleepPollInterval() async {
        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
