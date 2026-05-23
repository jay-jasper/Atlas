import Foundation

enum PrivacyPulseCategory: String, CaseIterable, Identifiable, Sendable {
    case camera
    case microphone
    case clipboard
    case screenRecording
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera:
            return "Camera"
        case .microphone:
            return "Microphone"
        case .clipboard:
            return "Clipboard"
        case .screenRecording:
            return "Screen Recording"
        case .accessibility:
            return "Accessibility"
        }
    }
}

enum PrivacyPulseStatus: Equatable, Sendable {
    case allowed
    case denied
    case notDetermined
    case recentlyUsed(Date)
    case inactive

    var label: String {
        switch self {
        case .allowed:
            return "Allowed"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Determined"
        case .recentlyUsed:
            return "Recently Used"
        case .inactive:
            return "Inactive"
        }
    }
}

struct PrivacyPulseEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let category: PrivacyPulseCategory
    let title: String
    let detail: String
    let occurredAt: Date
}

struct PrivacyPulseSnapshot: Equatable, Sendable {
    let statuses: [PrivacyPulseCategory: PrivacyPulseStatus]
    let events: [PrivacyPulseEvent]

    func status(for category: PrivacyPulseCategory) -> PrivacyPulseStatus {
        statuses[category] ?? .inactive
    }
}

protocol PrivacyPulseEventStoring {
    func record(_ event: PrivacyPulseEvent)
    func recentEvents(limit: Int) -> [PrivacyPulseEvent]
    func mostRecentEventDate(for category: PrivacyPulseCategory) -> Date?
}

protocol PrivacyPulseStatusProviding {
    func cameraStatus() -> PrivacyPulseStatus
    func microphoneStatus() -> PrivacyPulseStatus
    func screenRecordingStatus() -> PrivacyPulseStatus
    func accessibilityStatus() -> PrivacyPulseStatus
}
