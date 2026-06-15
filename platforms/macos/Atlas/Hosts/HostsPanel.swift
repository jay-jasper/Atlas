import SwiftUI

struct HostsPanel: View {
    @ObservedObject var service: HostsService
    @State private var newIP = ""
    @State private var newHost = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Hosts Editor", systemImage: "network")
                    .font(.headline)
                Spacer()
                Button { service.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }

            ForEach(service.entries) { entry in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { entry.enabled },
                        set: { _ in service.toggle(hostname: entry.hostnames.first ?? "") }
                    ))
                    .labelsHidden()
                    .controlSize(.mini)

                    Text(entry.ip)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 110, alignment: .leading)
                    Text(entry.hostnames.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(entry.enabled ? .primary : .secondary)
                        .strikethrough(!entry.enabled)
                    Spacer()
                    Button(role: .destructive) { service.remove(id: entry.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                TextField("127.0.0.1", text: $newIP).frame(width: 110)
                TextField("example.test", text: $newHost)
                Button("Add") {
                    service.add(ip: newIP, hostname: newHost)
                    newIP = ""; newHost = ""
                }
                .disabled(newIP.isEmpty || newHost.isEmpty)
            }
            .textFieldStyle(.roundedBorder)

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
