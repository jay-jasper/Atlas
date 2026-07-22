import AVFoundation
import Foundation

/// Exports an edited `RecordingTimeline` to a movie file by stitching the
/// timeline's `exportSpans` from the source media via `AVMutableComposition`.
enum RecordingExporter {
    enum ExportError: Error, Equatable {
        case emptyTimeline
        case incompatibleSource
        case exportFailed(String)
    }

    /// Millisecond spans → CMTimeRanges against the source asset.
    /// Pure and unit-testable.
    static func timeRanges(forSpans spans: [(start: Int, end: Int)], timescale: CMTimeScale = 1000) -> [CMTimeRange] {
        spans.compactMap { span in
            guard span.end > span.start, span.start >= 0 else { return nil }
            return CMTimeRange(
                start: CMTime(value: CMTimeValue(span.start), timescale: timescale),
                duration: CMTime(value: CMTimeValue(span.end - span.start), timescale: timescale)
            )
        }
    }

    /// Stitch the timeline spans from `sourceURL` into `outputURL` (QuickTime
    /// .mov / .mp4 depending on extension; passthrough quality).
    static func export(
        timeline: RecordingTimeline,
        sourceURL: URL,
        outputURL: URL
    ) async throws {
        let ranges = timeRanges(forSpans: timeline.exportSpans)
        guard ranges.isEmpty == false else { throw ExportError.emptyTimeline }

        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard videoTracks.isEmpty == false || audioTracks.isEmpty == false else {
            throw ExportError.incompatibleSource
        }

        let compositionVideo = videoTracks.isEmpty ? nil : composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let compositionAudios = audioTracks.map { _ in
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        var cursor = CMTime.zero
        for range in ranges {
            if let videoTrack = videoTracks.first, let compositionVideo {
                try compositionVideo.insertTimeRange(range, of: videoTrack, at: cursor)
            }
            for (index, audioTrack) in audioTracks.enumerated() {
                try compositionAudios[index]?.insertTimeRange(range, of: audioTrack, at: cursor)
            }
            cursor = cursor + range.duration
        }

        if let videoTrack = videoTracks.first {
            let transform = try await videoTrack.load(.preferredTransform)
            compositionVideo?.preferredTransform = transform
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.exportFailed("无法创建导出会话")
        }
        session.outputURL = outputURL
        session.outputFileType = outputURL.pathExtension.lowercased() == "mov" ? .mov : .mp4

        try? FileManager.default.removeItem(at: outputURL)
        await session.export()

        switch session.status {
        case .completed:
            return
        case .failed, .cancelled:
            throw ExportError.exportFailed(session.error?.localizedDescription ?? "导出失败")
        default:
            throw ExportError.exportFailed("导出未完成")
        }
    }
}
