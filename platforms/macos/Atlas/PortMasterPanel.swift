import SwiftUI

struct MonitoringPortsPanel: View {
    @State private var portInput: String = ""
    @State private var lookupResult: MonitoringPortProcess?
    @State private var statusText: String = ""
    @State private var isError: Bool = false

    var body: some View {
        Group {
            Text("Ports").font(.subheadline).foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Port", text: $portInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("Lookup") {
                        lookupPort()
                    }
                    .disabled(portInput.isEmpty)
                }

                if let lookupResult {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(lookupResult.processName) (PID \(lookupResult.pid))")
                                .font(.caption)
                            Text("Port \(lookupResult.port)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Kill Process") {
                            killProcess(lookupResult)
                        }
                    }
                }

                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(isError ? .red : .secondary)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func lookupPort() {
        guard let port = UInt16(portInput) else {
            lookupResult = nil
            statusText = "Invalid port: \(portInput)"
            isError = true
            return
        }

        do {
            lookupResult = try AtlasBridge.lookupPort(port)
            if lookupResult == nil {
                statusText = "No process found for port \(port)"
                isError = false
            } else {
                statusText = ""
                isError = false
            }
        } catch {
            lookupResult = nil
            statusText = error.localizedDescription
            isError = true
        }
    }

    private func killProcess(_ process: MonitoringPortProcess) {
        do {
            let killed = try AtlasBridge.killPortProcess(pid: process.pid)
            if killed {
                lookupResult = nil
                statusText = "Killed \(process.processName) (PID \(process.pid))"
                isError = false
            } else {
                statusText = "Process was not killed"
                isError = true
            }
        } catch {
            statusText = error.localizedDescription
            isError = true
        }
    }
}
