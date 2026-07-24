import SwiftUI

struct PluginConsentView: View {
    @ObservedObject var service: PluginPlatformService
    let request: PluginConsentRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install \(request.name) \(request.version)?")
                .font(.headline)
            Text("Publisher: \(request.publisher)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Package: \(request.packageRoot)")
                .font(.caption2.monospaced())
                .lineLimit(1)
            if request.requested.isEmpty {
                Text("This plugin requests no privileged capabilities.")
            } else {
                ForEach(request.requested, id: \.self) { capability in
                    Toggle(
                        capability,
                        isOn: Binding(
                            get: { service.pendingConsent?.selected.contains(capability) == true },
                            set: { service.setCapability(capability, enabled: $0) }
                        )
                    )
                }
            }
            HStack {
                Button("Cancel", role: .cancel) { service.denyPendingConsent() }
                Spacer()
                Button("Install") { service.applyPendingConsent() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 380)
    }
}
