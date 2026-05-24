import SwiftUI

struct NetworkMonitorPanel: View {
    @ObservedObject var service: NetworkMonitorService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Network Monitor", systemImage: "network")
                    .font(.headline)
                Spacer()
                Button {
                    service.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh connections")
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter by app or address…", text: $service.filterText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(6)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            let items = service.filteredConnections
            if items.isEmpty {
                Text(service.status.isEmpty ? "No connections" : service.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { conn in
                            NetworkConnectionRow(connection: conn)
                        }
                    }
                }
                .frame(maxHeight: 220)

                Text("\(items.count) connection\(items.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .onAppear { service.startAutoRefresh() }
        .onDisappear { service.stopAutoRefresh() }
    }
}

private struct NetworkConnectionRow: View {
    let connection: NetworkConnection

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connection.isEstablished ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            Text(connection.processName)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 1) {
                Text(connection.remoteAddress)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("pid \(connection.pid)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
