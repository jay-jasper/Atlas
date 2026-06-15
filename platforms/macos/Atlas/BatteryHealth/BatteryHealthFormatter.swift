import Foundation

/// Pure presentation helpers for battery health. Fully unit-testable.
enum BatteryHealthFormatter {
    enum Condition: String {
        case normal = "Normal"
        case serviceRecommended = "Service Recommended"
        case replaceSoon = "Replace Soon"
    }

    /// Apple considers a battery healthy down to ~80%; below that, service is
    /// recommended; below ~60% it's failing.
    static func condition(healthPercent: Float) -> Condition {
        switch healthPercent {
        case ..<60: return .replaceSoon
        case ..<80: return .serviceRecommended
        default: return .normal
        }
    }

    /// Formats a time-to-empty/full in seconds as "2h 15m".
    static func formatTime(seconds: Int64?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func formatHealth(_ percent: Float) -> String {
        String(format: "%.0f%%", percent)
    }

    static func formatCycles(_ count: UInt32?) -> String {
        count.map { "\($0) cycles" } ?? "—"
    }
}
