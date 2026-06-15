import Foundation

/// Reads system-wide now-playing info from the private MediaRemote framework via
/// dlopen (no fictional symbols — these exist; the provider degrades gracefully
/// to nil if the framework or symbols are unavailable, e.g. on macOS versions
/// where Apple has restricted MediaRemote). Parsing is delegated to the testable
/// `NowPlayingParser`; this object only handles the dynamic binding + caching.
final class MediaRemoteNowPlayingProvider: NowPlayingProviding {
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

    private let getInfo: GetInfoFn?
    private let getIsPlaying: GetIsPlayingFn?
    private var cached: NowPlayingTrack?
    private var isPlaying = false
    private let lock = NSLock()

    init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        )
        getInfo = MediaRemoteNowPlayingProvider.bind(handle, "MRMediaRemoteGetNowPlayingInfo")
        getIsPlaying = MediaRemoteNowPlayingProvider.bind(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        refresh()
    }

    func current() -> NowPlayingTrack? {
        // Kick a refresh for next time, return the most recent cached snapshot.
        refresh()
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    /// Triggers the async MediaRemote queries; updates the cache when they return.
    func refresh() {
        getIsPlaying?(.main) { [weak self] playing in
            self?.lock.lock(); self?.isPlaying = playing; self?.lock.unlock()
        }
        getInfo?(.main) { [weak self] info in
            guard let self else { return }
            self.lock.lock()
            let playing = self.isPlaying
            self.cached = NowPlayingParser.parse(info: info, isPlaying: playing)
            self.lock.unlock()
        }
    }

    private static func bind<T>(_ handle: UnsafeMutableRawPointer?, _ symbol: String) -> T? {
        guard let handle, let sym = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
}
