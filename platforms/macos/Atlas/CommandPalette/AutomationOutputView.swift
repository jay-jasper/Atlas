import SwiftUI

@MainActor
final class AutomationOutputViewModel: ObservableObject {
    @Published private(set) var result: AutomationProcessResult?
    @Published private(set) var isRunning = false
    @Published var hasConfirmed = false

    let command: CustomAutomationCommand
    private let runner: AutomationProcessRunning

    init(command: CustomAutomationCommand, runner: AutomationProcessRunning) {
        self.command = command
        self.runner = runner
    }

    func run() {
        guard !isRunning else { return }
        guard result == nil else { return }
        guard !command.requiresConfirmation || hasConfirmed else { return }

        isRunning = true
        Task {
            let result = await runner.run(command)
            self.result = result
            self.isRunning = false
        }
    }
}

enum AutomationOutputFormatter {
    static func statusText(for result: AutomationProcessResult, timeoutSeconds: TimeInterval) -> String {
        if result.didTimeOut {
            return "Timed out after \(Int(timeoutSeconds))s"
        }
        return "Exited with code \(result.exitCode)"
    }

    static func displayText(for result: AutomationProcessResult) -> String {
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if stdout.isEmpty && stderr.isEmpty { return "No output" }
        if stderr.isEmpty { return stdout }
        if stdout.isEmpty { return stderr }
        return "\(stdout)\n\n\(stderr)"
    }
}

struct AutomationOutputView: View {
    @StateObject private var model: AutomationOutputViewModel

    init(command: CustomAutomationCommand, runner: AutomationProcessRunning) {
        _model = StateObject(wrappedValue: AutomationOutputViewModel(command: command, runner: runner))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.command.title)
                .font(.headline)

            if model.command.requiresConfirmation && !model.hasConfirmed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("This automation can run local code on your Mac.", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(model.command.command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Allow and Run") {
                        model.hasConfirmed = true
                        model.run()
                    }
                }
            } else if model.isRunning {
                ProgressView("Running...")
            } else if let result = model.result {
                output(result)
            } else {
                Button("Run") { model.run() }
            }
        }
        .padding()
        .onAppear {
            if !model.command.requiresConfirmation {
                model.hasConfirmed = true
                model.run()
            }
        }
    }

    private func output(_ result: AutomationProcessResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                AutomationOutputFormatter.statusText(for: result, timeoutSeconds: model.command.timeoutSeconds),
                systemImage: result.exitCode == 0 && !result.didTimeOut ? "checkmark.circle" : "xmark.octagon"
            )
            ScrollView {
                Text(AutomationOutputFormatter.displayText(for: result))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
        }
    }
}
