import XCTest
@testable import Atlas

final class PrivacyPulseServiceTests: XCTestCase {
    func testSnapshotIncludesInjectedPermissionStatusesAndRecentEvents() {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = FakePrivacyPulseEventStore(events: [
            Self.event(category: .clipboard, title: "Clipboard Read", occurredAt: now.addingTimeInterval(-10)),
            Self.event(category: .screenRecording, title: "Screen Capture", occurredAt: now.addingTimeInterval(-20)),
            Self.event(category: .accessibility, title: "Accessibility Check", occurredAt: now.addingTimeInterval(-30)),
        ])
        let service = PrivacyPulseService(
            statusProvider: FakePrivacyPulseStatusProvider(
                camera: .allowed,
                microphone: .denied,
                screenRecording: .allowed,
                accessibility: .allowed
            ),
            eventStore: store,
            recentUsageInterval: 60
        )

        let snapshot = service.snapshot(now: now)

        XCTAssertEqual(snapshot.status(for: .camera), .allowed)
        XCTAssertEqual(snapshot.status(for: .microphone), .denied)
        XCTAssertEqual(snapshot.status(for: .clipboard), .recentlyUsed(now.addingTimeInterval(-10)))
        XCTAssertEqual(snapshot.status(for: .screenRecording), .recentlyUsed(now.addingTimeInterval(-20)))
        XCTAssertEqual(snapshot.status(for: .accessibility), .recentlyUsed(now.addingTimeInterval(-30)))
        XCTAssertEqual(snapshot.events.map(\.title), ["Clipboard Read", "Screen Capture", "Accessibility Check"])
    }

    func testStaleAtlasAccessFallsBackToInactiveOrPermissionStatus() {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = FakePrivacyPulseEventStore(events: [
            Self.event(category: .clipboard, title: "Clipboard Read", occurredAt: now.addingTimeInterval(-600)),
            Self.event(category: .screenRecording, title: "Screen Capture", occurredAt: now.addingTimeInterval(-600)),
        ])
        let service = PrivacyPulseService(
            statusProvider: FakePrivacyPulseStatusProvider(screenRecording: .allowed),
            eventStore: store,
            recentUsageInterval: 60
        )

        let snapshot = service.snapshot(now: now)

        XCTAssertEqual(snapshot.status(for: .clipboard), .inactive)
        XCTAssertEqual(snapshot.status(for: .screenRecording), .allowed)
    }

    func testAccessLoggerCapsEventsAndReturnsNewestFirst() {
        var tick = 0
        let logger = PrivacyPulseAccessLogger(maxEvents: 2) {
            defer { tick += 1 }
            return Date(timeIntervalSince1970: TimeInterval(tick))
        }

        logger.record(category: .clipboard, title: "First", detail: "first")
        logger.record(category: .accessibility, title: "Second", detail: "second")
        logger.record(category: .screenRecording, title: "Third", detail: "third")

        let events = logger.recentEvents(limit: 10)
        XCTAssertEqual(events.map(\.title), ["Third", "Second"])
        XCTAssertEqual(logger.mostRecentEventDate(for: .screenRecording), Date(timeIntervalSince1970: 2))
        XCTAssertNil(logger.mostRecentEventDate(for: .clipboard))
    }

    private static func event(
        category: PrivacyPulseCategory,
        title: String,
        occurredAt: Date
    ) -> PrivacyPulseEvent {
        PrivacyPulseEvent(
            id: UUID(),
            category: category,
            title: title,
            detail: title,
            occurredAt: occurredAt
        )
    }
}

private final class FakePrivacyPulseEventStore: PrivacyPulseEventStoring {
    private var events: [PrivacyPulseEvent]

    init(events: [PrivacyPulseEvent] = []) {
        self.events = events
    }

    func record(_ event: PrivacyPulseEvent) {
        events.insert(event, at: 0)
    }

    func recentEvents(limit: Int) -> [PrivacyPulseEvent] {
        Array(events.prefix(limit))
    }

    func mostRecentEventDate(for category: PrivacyPulseCategory) -> Date? {
        events.first { $0.category == category }?.occurredAt
    }
}

private struct FakePrivacyPulseStatusProvider: PrivacyPulseStatusProviding {
    var camera: PrivacyPulseStatus = .inactive
    var microphone: PrivacyPulseStatus = .inactive
    var screenRecording: PrivacyPulseStatus = .inactive
    var accessibility: PrivacyPulseStatus = .inactive

    func cameraStatus() -> PrivacyPulseStatus { camera }
    func microphoneStatus() -> PrivacyPulseStatus { microphone }
    func screenRecordingStatus() -> PrivacyPulseStatus { screenRecording }
    func accessibilityStatus() -> PrivacyPulseStatus { accessibility }
}
