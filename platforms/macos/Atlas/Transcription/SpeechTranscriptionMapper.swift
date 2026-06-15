import Foundation

/// Groups word-level recognition results into readable, timestamped lines.
/// Pure — the testable boundary between Speech/Whisper output and TranscriptSegment.
enum SpeechTranscriptionMapper {
    /// A single recognized word with its time span (milliseconds).
    struct Word: Equatable {
        let text: String
        let startMs: Int
        let endMs: Int
    }

    /// Groups words into segments, breaking on sentence-ending punctuation or
    /// after `maxWords`. Each segment spans from its first word's start to its
    /// last word's end.
    static func group(words: [Word], maxWords: Int = 12) -> [TranscriptSegment] {
        guard !words.isEmpty else { return [] }
        var segments: [TranscriptSegment] = []
        var buffer: [Word] = []

        func flush() {
            guard let first = buffer.first, let last = buffer.last else { return }
            let text = buffer.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            segments.append(TranscriptSegment(startMs: first.startMs, endMs: last.endMs, text: text))
            buffer.removeAll()
        }

        for word in words {
            buffer.append(word)
            let endsSentence = word.text.hasSuffix(".") || word.text.hasSuffix("?") || word.text.hasSuffix("!")
            if endsSentence || buffer.count >= maxWords {
                flush()
            }
        }
        flush()
        return segments
    }
}
