import Foundation

enum NowPlayingProviderFactory {
    static func make() -> any NowPlayingProviding {
        #if ATLAS_STORE
        return UnavailableNowPlayingProvider()
        #else
        return MediaRemoteNowPlayingProvider()
        #endif
    }
}
