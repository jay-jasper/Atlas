import SwiftUI

struct AudioMeterPanel: View {
    @ObservedObject var service: AudioMeterService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Audio Level Meter", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                if service.isRunning {
                    Button("Stop") { service.stop() }.controlSize(.small)
                } else {
                    Button("Start") { service.start() }.controlSize(.small).buttonStyle(.borderedProminent)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(meterColor)
                        .frame(width: geo.size.width * CGFloat(service.level))
                }
            }
            .frame(height: 16)

            HStack {
                Text(String(format: "Peak: %.1f dBFS", service.peakDB))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
            }

            Text("Real-time microphone input level.")
                .font(.caption).foregroundStyle(.secondary)

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var meterColor: Color {
        switch service.level {
        case ..<0.6: return .green
        case ..<0.85: return .yellow
        default: return .red
        }
    }
}
