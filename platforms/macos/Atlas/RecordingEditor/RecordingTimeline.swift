import Foundation

/// A clip referencing a span of a source recording (milliseconds).
struct RecordingClip: Equatable, Identifiable {
    let id: UUID
    var sourceStartMs: Int
    var sourceEndMs: Int

    init(id: UUID = UUID(), sourceStartMs: Int, sourceEndMs: Int) {
        self.id = id
        self.sourceStartMs = sourceStartMs
        self.sourceEndMs = sourceEndMs
    }

    var durationMs: Int { max(0, sourceEndMs - sourceStartMs) }
}

/// An ordered list of clips forming an edited recording. Trim/split/remove are
/// pure operations on source spans; the AVFoundation export reads this model.
/// Fully unit-testable.
struct RecordingTimeline: Equatable {
    private(set) var clips: [RecordingClip]

    init(sourceDurationMs: Int) {
        clips = [RecordingClip(sourceStartMs: 0, sourceEndMs: max(0, sourceDurationMs))]
    }

    init(clips: [RecordingClip]) {
        self.clips = clips
    }

    /// Total output duration: the sum of all clip durations.
    var totalDurationMs: Int {
        clips.reduce(0) { $0 + $1.durationMs }
    }

    /// Trims a clip's in/out points (clamped so start <= end).
    mutating func trim(id: UUID, startMs: Int, endMs: Int) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let lo = max(0, min(startMs, endMs))
        let hi = max(startMs, endMs)
        clips[index].sourceStartMs = lo
        clips[index].sourceEndMs = hi
    }

    /// Splits the clip at the given offset (ms) measured within that clip's own
    /// span, producing two adjacent clips. No-op at the clip boundaries.
    mutating func split(id: UUID, atClipOffsetMs offset: Int) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = clips[index]
        let cut = clip.sourceStartMs + offset
        guard cut > clip.sourceStartMs, cut < clip.sourceEndMs else { return }
        let first = RecordingClip(sourceStartMs: clip.sourceStartMs, sourceEndMs: cut)
        let second = RecordingClip(sourceStartMs: cut, sourceEndMs: clip.sourceEndMs)
        clips.replaceSubrange(index...index, with: [first, second])
    }

    mutating func remove(id: UUID) {
        clips.removeAll { $0.id == id }
    }

    mutating func move(from: Int, to: Int) {
        guard clips.indices.contains(from), to >= 0, to <= clips.count else { return }
        let clip = clips.remove(at: from)
        clips.insert(clip, at: min(to, clips.count))
    }

    /// The source spans (start, end) the exporter composites, in order.
    var exportSpans: [(start: Int, end: Int)] {
        clips.map { ($0.sourceStartMs, $0.sourceEndMs) }
    }
}
