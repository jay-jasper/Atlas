import Foundation

/// Which capture sources are currently active.
struct RecordingStatus: Equatable {
    var microphone: Bool
    var camera: Bool
    var screen: Bool

    static let idle = RecordingStatus(microphone: false, camera: false, screen: false)

    var isActive: Bool { microphone || camera || screen }

    /// Active sources in a stable display order.
    var activeSources: [String] {
        var sources: [String] = []
        if camera { sources.append("Camera") }
        if microphone { sources.append("Microphone") }
        if screen { sources.append("Screen") }
        return sources
    }

    /// A short label, e.g. "Recording: Camera, Microphone" or "Not recording".
    var label: String {
        isActive ? "Recording: \(activeSources.joined(separator: ", "))" : "Not recording"
    }

    /// SF Symbol representing the most significant active source.
    var systemImage: String {
        if camera { return "video.fill" }
        if screen { return "rectangle.dashed.badge.record" }
        if microphone { return "mic.fill" }
        return "record.circle"
    }
}
