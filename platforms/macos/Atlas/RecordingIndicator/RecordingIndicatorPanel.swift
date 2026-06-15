import SwiftUI

struct RecordingIndicatorPanel: View {
    @ObservedObject var service: RecordingIndicatorService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recording Indicator", systemImage: "record.circle")
                    .font(.headline)
                Spacer()
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: service.status.systemImage)
                    .foregroundStyle(service.status.isActive ? .red : .secondary)
                Text(service.status.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(service.status.isActive ? .primary : .secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (service.status.isActive ? Color.red.opacity(0.12) : Color.secondary.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: 8)
            )

            HStack(spacing: 12) {
                sourceTag("Camera", "video", service.status.camera)
                sourceTag("Mic", "mic", service.status.microphone)
                sourceTag("Screen", "rectangle.dashed", service.status.screen)
            }

            Text("Warns you when capture devices are in use, so recordings aren't forgotten.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func sourceTag(_ name: String, _ icon: String, _ active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(name).font(.caption)
        }
        .foregroundStyle(active ? Color.red : .secondary)
    }
}
