import SwiftUI

struct PacketMonitorPanel: View {
    @ObservedObject var service: PacketMonitorService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Packet Monitor", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                Button("Refresh") { service.refresh() }.controlSize(.small)
            }

            if service.traffic.isEmpty {
                Text(service.statusMessage.isEmpty ? "Refresh to see per-process traffic." : service.statusMessage)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(service.traffic.prefix(12)) { item in
                    HStack {
                        Text(item.process).font(.caption).lineLimit(1)
                        Spacer()
                        Label(PacketMonitorService.formatBytes(item.bytesIn), systemImage: "arrow.down")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.blue)
                        Label(PacketMonitorService.formatBytes(item.bytesOut), systemImage: "arrow.up")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.green)
                    }
                }
            }
        }
    }
}
