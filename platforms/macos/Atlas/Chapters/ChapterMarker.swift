import Foundation

/// A timestamped chapter marker (seconds from the start of a recording).
struct ChapterMarker: Equatable, Identifiable {
    let id: UUID
    var seconds: Int
    var title: String

    init(id: UUID = UUID(), seconds: Int, title: String) {
        self.id = id
        self.seconds = seconds
        self.title = title
    }
}

/// Exports chapter markers to common formats. Pure formatting — fully testable.
enum ChapterExporter {
    enum Format: String, CaseIterable {
        case youtube
        case srt
        case podcast // Simple "Chapters" plain text
    }

    static func export(_ markers: [ChapterMarker], as format: Format) -> String {
        let sorted = markers.sorted { $0.seconds < $1.seconds }
        switch format {
        case .youtube:
            // YouTube requires the first chapter at 00:00.
            return sorted.map { "\(timestamp($0.seconds, includeHours: needsHours(sorted))) \($0.title)" }
                .joined(separator: "\n")
        case .srt:
            return sorted.enumerated().map { index, marker in
                let end = index + 1 < sorted.count ? sorted[index + 1].seconds : marker.seconds + 5
                return "\(index + 1)\n\(srtTime(marker.seconds)) --> \(srtTime(end))\n\(marker.title)"
            }.joined(separator: "\n\n") + "\n"
        case .podcast:
            return sorted.map { "(\(timestamp($0.seconds, includeHours: true))) \($0.title)" }
                .joined(separator: "\n")
        }
    }

    static func timestamp(_ seconds: Int, includeHours: Bool) -> String {
        let clamped = max(0, seconds)
        let s = clamped % 60
        let m = (clamped / 60) % 60
        let h = clamped / 3600
        return includeHours || h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    static func srtTime(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d:%02d,000", clamped / 3600, (clamped / 60) % 60, clamped % 60)
    }

    private static func needsHours(_ markers: [ChapterMarker]) -> Bool {
        (markers.last?.seconds ?? 0) >= 3600
    }
}
