import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptionPanel: View {
    @ObservedObject var service: TranscriptionService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Transcription", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Picker("", selection: $service.model) {
                    ForEach(WhisperModel.allCases) { Text("\($0.displayName) · \($0.sizeMB)MB").tag($0) }
                }
                .frame(width: 150)
            }

            HStack {
                Button("Choose Audio…") { chooseFile() }
                    .buttonStyle(.borderedProminent)
                if service.isTranscribing { ProgressView().controlSize(.small) }
                if !service.segments.isEmpty {
                    Button("Copy SRT") { service.copySRT() }.controlSize(.small)
                }
            }

            if !service.segments.isEmpty {
                ScrollView {
                    Text(service.plainText())
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            } else {
                Text("Transcribe audio/video to text and SRT locally with Whisper.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .wav, .mp3]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            service.transcribe(url: url)
        }
    }
}
