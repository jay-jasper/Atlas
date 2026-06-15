import SwiftUI

struct BluetoothBatteryPanel: View {
    @ObservedObject var service: BluetoothBatteryService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Bluetooth Battery", systemImage: "airpods")
                    .font(.headline)
                Spacer()
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }

            if service.devices.isEmpty {
                Text(service.statusMessage.isEmpty ? "Scanning…" : service.statusMessage)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(service.devices) { device in
                    HStack {
                        Image(systemName: icon(for: device.percent))
                            .foregroundStyle(color(for: device.percent))
                        Text(device.name).font(.caption.weight(.medium))
                        Spacer()
                        Text("\(device.percent)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(color(for: device.percent))
                    }
                }
            }
        }
    }

    private func icon(for percent: Int) -> String {
        percent <= 20 ? "battery.25" : (percent <= 50 ? "battery.50" : "battery.100")
    }

    private func color(for percent: Int) -> Color {
        percent <= 20 ? .red : (percent <= 50 ? .orange : .green)
    }
}
