import SwiftUI

struct ProxyPanel: View {
    @ObservedObject var service: ProxyService
    @State private var name = ""
    @State private var host = ""
    @State private var port = ""
    @State private var kind: ProxyKind = .http

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Proxy Switcher", systemImage: "network.badge.shield.half.filled")
                    .font(.headline)
                Spacer()
                Button("Disable") { service.disableAll() }
                    .controlSize(.small)
            }

            ForEach(service.profiles) { profile in
                HStack {
                    Image(systemName: service.activeProfileID == profile.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(service.activeProfileID == profile.id ? .green : .secondary)
                    Text(profile.name).font(.caption.weight(.medium))
                    Text("\(profile.kind.rawValue.uppercased()) \(profile.host):\(profile.port)")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply") { service.apply(profile) }
                        .controlSize(.mini)
                    Button(role: .destructive) { service.delete(id: profile.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                TextField("Name", text: $name).frame(width: 80)
                Picker("", selection: $kind) {
                    ForEach(ProxyKind.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                .frame(width: 80)
                TextField("host", text: $host)
                TextField("port", text: $port).frame(width: 56)
                Button("Add") {
                    service.add(ProxyProfile(name: name, kind: kind, host: host, port: Int(port) ?? 0))
                    if service.statusMessage.isEmpty { name = ""; host = ""; port = "" }
                }
                .disabled(name.isEmpty || host.isEmpty || port.isEmpty)
            }
            .textFieldStyle(.roundedBorder)

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
