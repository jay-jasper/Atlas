import AppKit
import Foundation

@MainActor
final class TranscriptionService: ObservableObject {
    @Published var model: WhisperModel = .base
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var isTranscribing = false
    @Published private(set) var statusMessage = ""

    private let transcriber: Transcribing

    init(transcriber: Transcribing = UnavailableTranscriber()) {
        self.transcriber = transcriber
    }

    func transcribe(url: URL) {
        isTranscribing = true
        statusMessage = ""
        let transcriber = self.transcriber
        let model = self.model
        Task.detached(priority: .userInitiated) {
            do {
                let result = try transcriber.transcribe(fileURL: url, model: model)
                await MainActor.run {
                    self.segments = result
                    self.isTranscribing = false
                    self.statusMessage = result.isEmpty ? "No speech detected." : ""
                }
            } catch {
                await MainActor.run {
                    self.isTranscribing = false
                    self.statusMessage = "Transcription unavailable — download the \(model.displayName) model."
                }
            }
        }
    }

    func exportSRT() -> String { TranscriptionFormatter.srt(segments) }
    func plainText() -> String { TranscriptionFormatter.plainText(segments) }

    func copySRT() {
        guard !segments.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportSRT(), forType: .string)
    }
}

/// Placeholder transcriber used until whisper.cpp is wired; always throws.
struct UnavailableTranscriber: Transcribing {
    struct NotInstalled: Error {}
    func transcribe(fileURL: URL, model: WhisperModel) throws -> [TranscriptSegment] {
        throw NotInstalled()
    }
}
