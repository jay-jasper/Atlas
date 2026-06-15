import SwiftUI

struct LANTransferPanel: View {
    @ObservedObject var service: LANTransferService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LAN Transfer", systemImage: "wifi.circle")
                    .font(.headline)
                Spacer()
                Toggle("Receive", isOn: Binding(
                    get: { service.isAdvertising },
                    set: { $0 ? service.startReceiving() : service.stopReceiving() }
                ))
                .toggleStyle(.switch).controlSize(.mini)
            }

            HStack {
                Button("Find Peers") { service.browse() }.controlSize(.small)
                Spacer()
            }

            if service.peers.isEmpty {
                Text("No peers found yet. Enable Receive on another Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(service.peers) { peer in
                    HStack {
                        Image(systemName: "laptopcomputer").foregroundStyle(.secondary)
                        Text(peer.name).font(.caption)
                        Spacer()
                        Button("Send…") {}.controlSize(.mini).disabled(true)
                    }
                }
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
