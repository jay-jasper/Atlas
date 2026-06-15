import AVFoundation
import Foundation

@MainActor
final class RecordingEditorService: ObservableObject {
    @Published private(set) var timeline = RecordingTimeline(sourceDurationMs: 0)
    @Published private(set) var sourceURL: URL?
    @Published private(set) var statusMessage = ""

    /// Loads a recording and seeds a single full-length clip.
    func load(url: URL) {
        sourceURL = url
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
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

    var totalDurationLabel: String {
        let total = timeline.totalDurationMs
        return String(format: "%d:%02d.%03d", total / 60000, (total / 1000) % 60, total % 1000)
    }
}
