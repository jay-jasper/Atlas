import SwiftUI

struct EnvPanel: View {
    @ObservedObject var service: EnvService
    @State private var key = ""
    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Env Variables", systemImage: "terminal.fill")
                    .font(.headline)
                Spacer()
                Button { service.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }

            if service.variables.isEmpty {
                Text("No Atlas-managed variables. Add one below.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(service.variables) { variable in
                HStack {
                    Text(variable.key)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                    Text("=").foregroundStyle(.secondary)
                    Text(variable.value).font(.system(.caption, design: .monospaced)).lineLimit(1)
                    Spacer()
                    Button(role: .destructive) { service.remove(key: variable.key) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                TextField("KEY", text: $key).frame(width: 120)
                TextField("value", text: $value)
                Button("Set") {
                    service.set(key: key, value: value)
                    key = ""; value = ""
                }
                .disabled(key.isEmpty)
            }
            .textFieldStyle(.roundedBorder)

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
