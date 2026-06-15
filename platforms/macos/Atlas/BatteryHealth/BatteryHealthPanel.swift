import SwiftUI

struct BatteryHealthPanel: View {
    @ObservedObject var service: BatteryHealthService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Battery Health", systemImage: "battery.100")
                    .font(.headline)
                Spacer()
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }

            if let battery = service.snapshot {
                let condition = BatteryHealthFormatter.condition(healthPercent: battery.healthPercent)
                metric("Charge", String(format: "%.0f%%", battery.chargePercent) + (battery.isCharging ? " ⚡︎" : ""))
                metric("Health", BatteryHealthFormatter.formatHealth(battery.healthPercent))
                metric("Condition", condition.rawValue, color: color(for: condition))
                metric("Cycle Count", BatteryHealthFormatter.formatCycles(battery.cycleCount))
                if let remaining = BatteryHealthFormatter.formatTime(seconds: battery.timeToEmptySecs) {
                    metric("Time Remaining", remaining)
                } else if let full = BatteryHealthFormatter.formatTime(seconds: battery.timeToFullSecs) {
                    metric("Time to Full", full)
                }
            } else {
                Text("No battery detected (desktop Mac).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(color)
        }
    }

    private func color(for condition: BatteryHealthFormatter.Condition) -> Color {
        switch condition {
        case .normal: return .green
        case .serviceRecommended: return .orange
        case .replaceSoon: return .red
        }
    }
}
