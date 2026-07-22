import Foundation

enum DistributionChannel: String {
    case appStore
    case direct

    static var current: DistributionChannel {
        #if ATLAS_STORE
        .appStore
        #else
        .direct
        #endif
    }
}

enum DistributionPolicy {
    static var allowsExecutablePlugins: Bool { DistributionChannel.current == .direct }
    static var allowsPrivilegedOperations: Bool { DistributionChannel.current == .direct }
    static var allowsExternalUpdater: Bool { DistributionChannel.current == .direct }
}
