import AppKit
import Foundation

@MainActor
final class TranscriptionService: ObservableObject {
    @Published var model: WhisperModel = .base
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var isTranscribing = false
    @Published private(set) var statusMessage = ""
    @Published private(set) var isDownloadingModel = false

    private let transcriber: Transcribing
    private let modelStore: WhisperModelStore

    init(
        transcriber: Transcribing = WhisperCLITranscriber(),
        modelStore: WhisperModelStore = WhisperModelStore()
    ) {
        self.transcriber = transcriber
        self.modelStore = modelStore
    }

    var isSelectedModelInstalled: Bool { modelStore.isInstalled(model) }

    func downloadSelectedModel() {
        let selectedModel = model
        isDownloadingModel = true
        statusMessage = "Downloading \(selectedModel.displayName) model…"
        modelStore.download(selectedModel) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.isDownloadingModel = false
                switch result {
                case .success:
                    self?.statusMessage = "\(selectedModel.displayName) model is ready."
                case .failure(let error):
                    self?.statusMessage = error.localizedDescription
                }
            }
        }
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
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func exportSRT() -> String { TranscriptionFormatter.srt(segments) }
    func plainText() -> String { TranscriptionFormatter.plainText(segments) }

    func copySRT() {
        guard !segments.isEmpty else { return }
        _ = NSPasteboard.general.clearContents()
        _ = NSPasteboard.general.setString(exportSRT(), forType: .string)
    }
}

/// Placeholder transcriber used until whisper.cpp is wired; always throws.
struct UnavailableTranscriber: Transcribing {
    struct NotInstalled: Error {}
    func transcribe(fileURL: URL, model: WhisperModel) throws -> [TranscriptSegment] {
        throw NotInstalled()
    }
}
