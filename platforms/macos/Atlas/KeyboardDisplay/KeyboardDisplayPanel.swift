import SwiftUI

struct KeyboardDisplayPanel: View {
    @ObservedObject var service: KeyboardDisplayService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Keyboard Display", systemImage: "keyboard")
                    .font(.headline)
                Spacer()
                Toggle("Capture", isOn: Binding(
                    get: { service.isCapturing },
                    set: { $0 ? service.startCapture() : service.stopCapture() }
                ))
                .toggleStyle(.switch).controlSize(.mini)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(service.recent) { stroke in
                        Text(stroke.text)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 36)

            HStack {
                if service.recent.isEmpty {
                    Text("Captured keystrokes appear here.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Clear") { service.clear() }.controlSize(.small)
                }
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
