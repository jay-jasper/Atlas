import Foundation

final class PrivacyPulseService {
    private let statusProvider: PrivacyPulseStatusProviding
    private let eventStore: PrivacyPulseEventStoring
    private let recentUsageInterval: TimeInterval

    init(
        statusProvider: PrivacyPulseStatusProviding,
        eventStore: PrivacyPulseEventStoring,
        recentUsageInterval: TimeInterval = 300
    ) {
        self.statusProvider = statusProvider
        self.eventStore = eventStore
        self.recentUsageInterval = recentUsageInterval
    }

    func snapshot(now: Date = Date(), eventLimit: Int = 20) -> PrivacyPulseSnapshot {
        PrivacyPulseSnapshot(
            statuses: [
                .camera: statusProvider.cameraStatus(),
                .microphone: statusProvider.microphoneStatus(),
                .clipboard: derivedStatus(for: .clipboard, now: now),
                .screenRecording: mergedStatus(
                    permissionStatus: statusProvider.screenRecordingStatus(),
                    category: .screenRecording,
                    now: now
                ),
                .accessibility: mergedStatus(
                    permissionStatus: statusProvider.accessibilityStatus(),
                    category: .accessibility,
                    now: now
                ),
            ],
            events: eventStore.recentEvents(limit: eventLimit)
        )
    }

    private func derivedStatus(for category: PrivacyPulseCategory, now: Date) -> PrivacyPulseStatus {
        guard let date = eventStore.mostRecentEventDate(for: category) else {
            return .inactive
        }

        return now.timeIntervalSince(date) <= recentUsageInterval ? .recentlyUsed(date) : .inactive
    }

    private func mergedStatus(
        permissionStatus: PrivacyPulseStatus,
        category: PrivacyPulseCategory,
        now: Date
    ) -> PrivacyPulseStatus {
        if case .allowed = permissionStatus,
           let date = eventStore.mostRecentEventDate(for: category),
           now.timeIntervalSince(date) <= recentUsageInterval {
            return .recentlyUsed(date)
        }

        return permissionStatus
    }
}
