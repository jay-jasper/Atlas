import AppKit
import SwiftUI

struct AudioRecordingPanel: View {
    @ObservedObject var service: AudioRecordingService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Audio Recording", systemImage: "waveform.badge.mic")
                    .font(.headline)
                Spacer()
                if service.isRecording {
                    Circle().fill(.red).frame(width: 8, height: 8)
                }
            }

            Picker("Format", selection: $service.format) {
                ForEach(AudioRecordingFormat.allCases) { Text($0.title).tag($0) }
            }
            .disabled(service.isRecording)

            HStack {
                if service.isRecording {
                    Button("Stop", role: .destructive) { service.stop() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Record") { service.start() }
                        .buttonStyle(.borderedProminent)
                }
                if let url = service.lastRecordingURL {
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .controlSize(.small)
                }
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
