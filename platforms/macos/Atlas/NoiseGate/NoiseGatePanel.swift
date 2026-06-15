import SwiftUI

struct NoiseGatePanel: View {
    @ObservedObject var service: NoiseGateService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Mic Noise Gate", systemImage: "mic.slash")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $service.isEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }

            HStack {
                Text("Threshold").font(.caption).frame(width: 70, alignment: .leading)
                Slider(value: $service.threshold, in: 0...0.2)
                Text(String(format: "%.3f", service.threshold))
                    .font(.caption.monospacedDigit()).frame(width: 44)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(service.isGateOpen ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(service.isGateOpen ? "Open (passing audio)" : "Closed (gated)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.6))
                        .frame(width: geo.size.width * CGFloat(service.inputLevel))
                }
            }
            .frame(height: 10)

            Text("Mutes the mic below the threshold to cut background noise.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
