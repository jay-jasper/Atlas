import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RecordingEditorPanel: View {
    @ObservedObject var service: RecordingEditorService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recording Editor", systemImage: "scissors")
                    .font(.headline)
                Spacer()
                Button("Open…") { chooseFile() }.controlSize(.small)
            }

            if service.sourceURL == nil {
                Text("Open a recording to trim, split, and rearrange clips.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Output: \(service.totalDurationLabel)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(service.timeline.clips.count) clip(s)").font(.caption2).foregroundStyle(.secondary)
                }

                ForEach(Array(service.timeline.clips.enumerated()), id: \.element.id) { index, clip in
                    HStack {
                        Text("Clip \(index + 1)").font(.caption.weight(.medium))
                        Text("\(clip.sourceStartMs)–\(clip.sourceEndMs)ms")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            service.split(id: clip.id, atClipOffsetMs: clip.durationMs / 2)
                        } label: { Image(systemName: "scissors") }
                            .buttonStyle(.plain)
                            .help("Split in half")
                        Button(role: .destructive) { service.remove(id: clip.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .audio]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            service.load(url: url)
        }
    }
}
