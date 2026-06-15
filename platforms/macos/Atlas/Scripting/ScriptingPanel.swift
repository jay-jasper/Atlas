import SwiftUI

struct ScriptingPanel: View {
    @ObservedObject var service: ScriptingService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Scripting", systemImage: "applescript")
                .font(.headline)

            TextEditor(text: $service.script)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))

            HStack {
                Button("Run") { service.run() }
                    .buttonStyle(.borderedProminent)
                if !service.output.isEmpty {
                    Text(service.output).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }

            DisclosureGroup("Available commands (\(service.availableCommands.count))") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(service.availableCommands, id: \.self) { command in
                        Text(command).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)

            Text("Automate Atlas with scripts (Lua bridge). Each line calls module.action.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
