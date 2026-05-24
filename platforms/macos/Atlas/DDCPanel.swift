import SwiftUI

struct DDCPanel: View {
    @ObservedObject var service: DisplayControlService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("DDC Monitor Control", systemImage: "display")
                    .font(.headline)
                Spacer()
                Button {
                    try? service.refreshDisplays()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh displays")
            }

            switch service.status {
            case .unavailable(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                let external = service.displays.filter { !$0.isBuiltin && $0.supportsDDC }
                if external.isEmpty {
                    Text("No DDC-capable external displays detected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(external) { display in
                        DisplayBrightnessRow(
                            display: display,
                            brightness: Binding(
                                get: { service.brightnessLevels[display.id] ?? 75 },
                                set: { service.setBrightness(for: display, to: $0) }
                            )
                        )
                    }
                }
            }
        }
        .padding()
        .onAppear {
            try? service.refreshDisplays()
            service.displays.filter { $0.supportsDDC }.forEach {
                service.refreshBrightness(for: $0)
            }
        }
    }
}

private struct DisplayBrightnessRow: View {
    let display: DisplayDevice
    @Binding var brightness: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(display.name, systemImage: "display.2")
                    .font(.subheadline)
                Spacer()
                Text("\(brightness)%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Slider(value: Binding(
                    get: { Double(brightness) },
                    set: { brightness = Int($0) }
                ), in: 0...100, step: 1)
                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
