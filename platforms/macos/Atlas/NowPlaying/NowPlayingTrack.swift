import Foundation

struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var elapsed: TimeInterval
    var duration: TimeInterval

    static let none = NowPlayingTrack(title: "", artist: "", album: "", isPlaying: false, elapsed: 0, duration: 0)

    var hasTrack: Bool { !title.isEmpty }
}

/// Pure presentation helpers for the now-playing widget. Fully unit-testable.
enum NowPlayingFormatter {
    /// Progress 0...1 through the track.
    static func progress(_ track: NowPlayingTrack) -> Double {
        guard track.duration > 0 else { return 0 }
        return min(1, max(0, track.elapsed / track.duration))
    }

    static func timeLabel(_ track: NowPlayingTrack) -> String {
        "\(format(track.elapsed)) / \(format(track.duration))"
    }

    static func subtitle(_ track: NowPlayingTrack) -> String {
        [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Supplies the current system now-playing track. The live implementation reads
/// the private MediaRemote framework; injected here so the model is testable and
/// the UI degrades gracefully when unavailable.
protocol NowPlayingProviding {
    func current() -> NowPlayingTrack?
}

/// Placeholder provider — returns nil until a MediaRemote-backed reader is wired.
struct UnavailableNowPlayingProvider: NowPlayingProviding {
    func current() -> NowPlayingTrack? { nil }
}
