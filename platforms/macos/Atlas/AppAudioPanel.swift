import SwiftUI

struct AppAudioPanel: View {
    @ObservedObject var service: AppAudioService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("App Audio", systemImage: "speaker.wave.3")
                    .font(.headline)
                Spacer()
                Button {
                    service.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh audio streams")
            }

            SystemVolumeRow(
                volume: $service.systemVolume,
                isMuted: service.isSystemMuted,
                onVolumeChange: { service.setSystemVolume($0) },
                onMuteToggle: { service.toggleSystemMute() }
            )

            if !service.streams.isEmpty {
                Divider()
                Text("Per-App Audio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(service.streams) { stream in
                    AppAudioStreamRow(
                        stream: stream,
                        onVolumeChange: { service.setVolume($0, for: stream) },
                        onMuteToggle: { service.toggleMute(for: stream) }
                    )
                }
            } else if !service.statusMessage.isEmpty {
                Text(service.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { service.refresh() }
    }
}

private struct SystemVolumeRow: View {
    @Binding var volume: Float
    let isMuted: Bool
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void

    var body: some View {
        VolumeRow(
            label: "System",
            icon: isMuted ? "speaker.slash" : "speaker.wave.2",
            volume: Binding(
                get: { Double(volume) },
                set: { onVolumeChange(Float($0)) }
            ),
            isMuted: isMuted,
            onMuteToggle: onMuteToggle
        )
    }
}

private struct AppAudioStreamRow: View {
    let stream: AppAudioStream
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void

    var body: some View {
        VolumeRow(
            label: stream.processName,
            icon: stream.isMuted ? "speaker.slash" : "speaker.wave.1",
            volume: Binding(
                get: { Double(stream.volume) },
                set: { onVolumeChange(Float($0)) }
            ),
            isMuted: stream.isMuted,
            onMuteToggle: onMuteToggle
        )
    }
}

private struct VolumeRow: View {
    let label: String
    let icon: String
    @Binding var volume: Double
    let isMuted: Bool
    let onMuteToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onMuteToggle) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(isMuted ? .secondary : .primary)
            }
            .buttonStyle(.plain)

            Text(label)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            Slider(value: $volume, in: 0...1)
                .disabled(isMuted)

            Text("\(Int(volume * 100))%")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(isMuted ? 0.6 : 1)
    }
}
