import Foundation

/// Parses a MediaRemote now-playing info dictionary into a `NowPlayingTrack`.
/// Pure — the testable boundary for the private-framework reader. Looks up both
/// the `kMRMediaRemoteNowPlayingInfo*` constant-name keys and short fallbacks so
/// it is robust to key-naming differences across macOS versions.
enum NowPlayingParser {
    static func parse(info: [String: Any], isPlaying: Bool) -> NowPlayingTrack? {
        let title = string(info, "Title")
        guard let title, !title.isEmpty else { return nil }
        return NowPlayingTrack(
            title: title,
            artist: string(info, "Artist") ?? "",
            album: string(info, "Album") ?? "",
            isPlaying: isPlaying,
            elapsed: number(info, "ElapsedTime") ?? 0,
            duration: number(info, "Duration") ?? 0
        )
    }

    private static func string(_ info: [String: Any], _ field: String) -> String? {
        value(info, field) as? String
    }

    private static func number(_ info: [String: Any], _ field: String) -> TimeInterval? {
        (value(info, field) as? NSNumber)?.doubleValue
    }

    /// Resolves a field by trying the MediaRemote constant-name key first, then a
    /// short fallback (e.g. "Title").
    private static func value(_ info: [String: Any], _ field: String) -> Any? {
        info["kMRMediaRemoteNowPlayingInfo\(field)"] ?? info[field]
    }
}
