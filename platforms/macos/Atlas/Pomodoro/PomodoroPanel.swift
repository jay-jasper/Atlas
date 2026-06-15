import SwiftUI

struct PomodoroPanel: View {
    @ObservedObject var service: PomodoroService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pomodoro", systemImage: "timer")
                    .font(.headline)
                Spacer()
                Text("\(service.completedFocusSessions) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Text(PomodoroEngine.format(seconds: service.remainingSeconds))
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(phaseColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(phaseLabel)
                        .font(.subheadline.weight(.medium))
                    Text(service.isRunning ? "Running" : "Idle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                if service.isRunning {
                    Button("Skip") { service.skip() }
                    Button("Reset", role: .destructive) { service.reset() }
                } else {
                    Button("Start Focus") { service.startFocus() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var phaseLabel: String {
        switch service.phase {
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        case .idle: return "Ready"
        }
    }

    private var phaseColor: Color {
        switch service.phase {
        case .focus: return .red
        case .shortBreak, .longBreak: return .green
        case .idle: return .primary
        }
    }
}
