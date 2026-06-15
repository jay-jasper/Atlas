import Foundation

/// A downloadable Whisper model. Sizes/URLs drive the download UI. Pure data.
enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny, base, small, medium, large

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    /// Approximate on-disk size in megabytes.
    var sizeMB: Int {
        switch self {
        case .tiny: return 75
        case .base: return 142
        case .small: return 466
        case .medium: return 1500
        case .large: return 2900
        }
    }

    /// Canonical ggml model download URL (Hugging Face).
    var downloadURL: String {
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(rawValue).bin"
    }

    /// Larger models are more accurate but slower; used to sort/recommend.
    var accuracyRank: Int { WhisperModel.allCases.firstIndex(of: self)! }
}

/// A timestamped transcript segment (ms-based, like SubtitleCue).
struct TranscriptSegment: Equatable {
    var startMs: Int
    var endMs: Int
    var text: String
}

/// Performs transcription of an audio file into segments. The live implementation
/// runs whisper.cpp; injected so the pipeline is testable.
protocol Transcribing {
    func transcribe(fileURL: URL, model: WhisperModel) throws -> [TranscriptSegment]
}

enum TranscriptionFormatter {
    /// Renders segments to SRT, reusing the subtitle document serializer.
    static func srt(_ segments: [TranscriptSegment]) -> String {
        let cues = segments.map { SubtitleCue(start: $0.startMs, end: $0.endMs, text: $0.text) }
        return SubtitleDocument.serialize(cues, format: .srt)
    }

    /// Plain-text transcript (segments joined).
    static func plainText(_ segments: [TranscriptSegment]) -> String {
        segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
