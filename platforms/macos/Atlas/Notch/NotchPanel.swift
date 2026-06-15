import SwiftUI

struct NotchPanel: View {
    @ObservedObject var service: NotchService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Notch Island", systemImage: "rectangle.topthird.inset.filled")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { service.isShown },
                    set: { show in show ? service.show { NotchIslandContent(expanded: service.isExpanded) } : service.hide() }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }

            HStack {
                Image(systemName: service.hasNotch ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(service.hasNotch ? .green : .orange)
                Text(service.hasNotch ? "Notch detected" : "No notch on this display")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Toggle("Expanded", isOn: Binding(
                get: { service.isExpanded },
                set: { _ in
                    service.toggleExpanded()
                    if service.isShown { service.show { NotchIslandContent(expanded: service.isExpanded) } }
                }
            ))
            .controlSize(.small)

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The content rendered inside the floating notch island window.
struct NotchIslandContent: View {
    let expanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note").foregroundStyle(.white)
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now Playing").font(.caption.weight(.semibold))
                    Text("Atlas Dynamic Island").font(.caption2)
                }
                .foregroundStyle(.white)
                Spacer()
                Image(systemName: "waveform").foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black, in: RoundedRectangle(cornerRadius: expanded ? 18 : 10))
    }
}
