import SwiftUI

struct OBSPanel: View {
    @ObservedObject var service: OBSService
    @State private var sceneName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("OBS Control", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(service.isConnected ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }

            if service.isConnected {
                HStack {
                    TextField("Scene name", text: $sceneName)
                        .textFieldStyle(.roundedBorder)
                    Button("Set Scene") { service.setScene(sceneName) }
                        .disabled(sceneName.isEmpty)
                }
                HStack {
                    Button("Toggle Record") { service.toggleRecord() }
                    Button("Toggle Stream") { service.toggleStream() }
                    Spacer()
                    Button("Disconnect", role: .destructive) { service.disconnect() }
                }
            } else {
                HStack {
                    TextField("Host", text: $service.host).frame(width: 90)
                    TextField("Port", text: $service.port).frame(width: 56)
                    SecureField("Password", text: $service.password)
                }
                .textFieldStyle(.roundedBorder)
                Button("Connect") { service.connect() }
                    .buttonStyle(.borderedProminent)
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
