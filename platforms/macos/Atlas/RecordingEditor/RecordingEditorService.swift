import AppKit
import AVFoundation
import Foundation

@MainActor
final class RecordingEditorService: ObservableObject {
    @Published private(set) var timeline = RecordingTimeline(sourceDurationMs: 0)
    @Published private(set) var sourceURL: URL?
    @Published private(set) var statusMessage = ""

    /// Loads a recording and seeds a single full-length clip.
    func load(url: URL) async {
        sourceURL = url
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let seconds = duration.map(CMTimeGetSeconds) ?? 0
        let ms = seconds.isFinite ? Int(seconds * 1000) : 0
        timeline = RecordingTimeline(sourceDurationMs: ms)
        statusMessage = ms > 0 ? "" : "Could not read media duration."
    }

    func trim(id: UUID, startMs: Int, endMs: Int) {
        timeline.trim(id: id, startMs: startMs, endMs: endMs)
    }

    func split(id: UUID, atClipOffsetMs offset: Int) {
        timeline.split(id: id, atClipOffsetMs: offset)
    }

    func remove(id: UUID) {
        timeline.remove(id: id)
    }

    @Published private(set) var isExporting = false

    /// Stitch the edited timeline into a new MP4 next to the source file.
    func exportEditedCopy() {
        guard let sourceURL, isExporting == false else { return }
        guard timeline.totalDurationMs > 0 else {
            statusMessage = "时间线为空，无可导出内容。"
            return
        }
        isExporting = true
        statusMessage = "正在导出…"
        let outputURL = sourceURL.deletingPathExtension()
            .appendingPathExtension("edited.mp4")
        let timeline = timeline
        Task {
            do {
                try await RecordingExporter.export(timeline: timeline, sourceURL: sourceURL, outputURL: outputURL)
                statusMessage = "已导出：\(outputURL.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } catch {
                statusMessage = "导出失败：\(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    var totalDurationLabel: String {
        let total = timeline.totalDurationMs
        return String(format: "%d:%02d.%03d", total / 60000, (total / 1000) % 60, total % 1000)
    }
}
