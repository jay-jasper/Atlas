import SwiftUI

struct TextExpansionPanel: View {
    @ObservedObject var service: TextExpansionService
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Text Expansion", systemImage: "text.cursor")
                    .font(.headline)
                Spacer()
                Toggle("Live", isOn: Binding(
                    get: { service.isMonitoring },
                    set: { $0 ? service.startMonitoring() : service.stopMonitoring() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            ForEach(service.snippets) { snippet in
                HStack {
                    Text(snippet.trigger)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text(snippet.expansion).font(.caption).lineLimit(1)
                    Spacer()
                    Button(role: .destructive) { service.delete(id: snippet.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                TextField(":sig", text: $trigger).frame(width: 80)
                TextField("expansion", text: $expansion)
                Button("Add") {
                    service.add(trigger: trigger, expansion: expansion)
                    if service.statusMessage.isEmpty { trigger = ""; expansion = "" }
                }
                .disabled(trigger.isEmpty || expansion.isEmpty)
            }
            .textFieldStyle(.roundedBorder)

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
