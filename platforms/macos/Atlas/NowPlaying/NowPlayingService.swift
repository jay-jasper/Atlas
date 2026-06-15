import AppKit
import Foundation

@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: NowPlayingTrack = .none
    @Published private(set) var statusMessage = ""

    private let provider: NowPlayingProviding

    init(provider: NowPlayingProviding = UnavailableNowPlayingProvider()) {
        self.provider = provider
        refresh()
    }

    func refresh() {
        if let current = provider.current() {
            track = current
            statusMessage = ""
        } else {
            track = .none
            statusMessage = "No track playing (or now-playing access unavailable)."
        }
    }

    /// Sends a media-key style play/pause via AppleScript to the active player.
    func togglePlayPause() {
        let script = "tell application \"System Events\" to key code 16 using {}" // F-key media play/pause fallback
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
        refresh()
    }
}
