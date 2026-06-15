import Foundation

/// A single subtitle cue with start/end times (in milliseconds) and text.
struct SubtitleCue: Equatable {
    var start: Int
    var end: Int
    var text: String
}

enum SubtitleFormat {
    case srt
    case vtt
}

/// Parses and serializes SRT and WebVTT subtitle documents, with time-shift and
/// format conversion. Pure value logic — no file IO — so it is fully testable.
enum SubtitleDocument {
    // MARK: - Parsing

    static func parse(_ content: String, format: SubtitleFormat) -> [SubtitleCue] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []
        for block in blocks {
            var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            // Skip a leading numeric index (SRT) or "WEBVTT" header / cue id.
            while let first = lines.first, !first.contains("-->") {
                if first.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("WEBVTT") {
                    lines.removeFirst()
                    continue
                }
                if Int(first.trimmingCharacters(in: .whitespaces)) != nil {
                    lines.removeFirst()
                    continue
                }
                break
            }
            guard let timeLine = lines.first, timeLine.contains("-->") else { continue }
            let times = timeLine.components(separatedBy: "-->")
            guard times.count == 2,
                  let start = parseTimestamp(times[0]),
                  let end = parseTimestamp(times[1]) else { continue }
            let text = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            cues.append(SubtitleCue(start: start, end: end, text: text))
        }
        return cues
    }

    /// Parses `HH:MM:SS,mmm` (SRT) or `HH:MM:SS.mmm` (VTT, hours optional).
    static func parseTimestamp(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let secondsParts = parts.last!.split(separator: ".").map(String.init)
        guard let seconds = Int(secondsParts[0]) else { return nil }
        let millis = secondsParts.count > 1 ? Int(secondsParts[1].padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0 : 0
        var hours = 0
        var minutes = 0
        if parts.count == 3 {
            hours = Int(parts[0]) ?? 0
            minutes = Int(parts[1]) ?? 0
        } else {
            minutes = Int(parts[0]) ?? 0
        }
        return ((hours * 3600 + minutes * 60 + seconds) * 1000) + millis
    }

    // MARK: - Serializing

    static func serialize(_ cues: [SubtitleCue], format: SubtitleFormat) -> String {
        switch format {
        case .srt:
            return cues.enumerated().map { index, cue in
                "\(index + 1)\n\(timestamp(cue.start, format: .srt)) --> \(timestamp(cue.end, format: .srt))\n\(cue.text)"
            }.joined(separator: "\n\n") + "\n"
        case .vtt:
            let body = cues.map { cue in
                "\(timestamp(cue.start, format: .vtt)) --> \(timestamp(cue.end, format: .vtt))\n\(cue.text)"
            }.joined(separator: "\n\n")
            return "WEBVTT\n\n" + body + "\n"
        }
    }

    static func timestamp(_ millis: Int, format: SubtitleFormat) -> String {
        let clamped = max(0, millis)
        let ms = clamped % 1000
        let totalSeconds = clamped / 1000
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        let separator = format == .srt ? "," : "."
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, seconds, separator, ms)
    }

    // MARK: - Transforms

    /// Shifts all cues by `offsetMillis` (can be negative). Clamps to 0.
    static func shift(_ cues: [SubtitleCue], byMillis offset: Int) -> [SubtitleCue] {
        cues.map { SubtitleCue(start: max(0, $0.start + offset), end: max(0, $0.end + offset), text: $0.text) }
    }

    static func convert(_ content: String, from: SubtitleFormat, to: SubtitleFormat) -> String {
        serialize(parse(content, format: from), format: to)
    }
}
