import Foundation

protocol PrivacyPulseAccessLogging {
    func record(category: PrivacyPulseCategory, title: String, detail: String)
}

final class PrivacyPulseAccessLogger: PrivacyPulseAccessLogging, PrivacyPulseEventStoring {
    private let maxEvents: Int
    private let dateProvider: () -> Date
    private let lock = NSLock()
    private var events: [PrivacyPulseEvent] = []

    init(maxEvents: Int = 100, dateProvider: @escaping () -> Date = Date.init) {
        self.maxEvents = maxEvents
        self.dateProvider = dateProvider
    }

    func record(category: PrivacyPulseCategory, title: String, detail: String) {
        record(
            PrivacyPulseEvent(
                id: UUID(),
                category: category,
                title: title,
                detail: detail,
                occurredAt: dateProvider()
            )
        )
    }

    func record(_ event: PrivacyPulseEvent) {
        lock.lock()
        defer { lock.unlock() }

        events.insert(event, at: 0)
        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }
    }

    func recentEvents(limit: Int) -> [PrivacyPulseEvent] {
        lock.lock()
        defer { lock.unlock() }

        return Array(events.prefix(max(0, limit)))
    }

    func mostRecentEventDate(for category: PrivacyPulseCategory) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        return events.first { $0.category == category }?.occurredAt
    }
}

struct NoopPrivacyPulseAccessLogger: PrivacyPulseAccessLogging {
    func record(category: PrivacyPulseCategory, title: String, detail: String) {}
}
