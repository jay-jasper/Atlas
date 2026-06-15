import XCTest
@testable import Atlas

@MainActor
final class PrivacyPulsePanelTests: XCTestCase {
    func testPanelStateIncludesAllStatusRowsInStableOrder() {
        let date = Date(timeIntervalSince1970: 100)
        let state = PrivacyPulsePanelState(snapshot: PrivacyPulseSnapshot(
            statuses: [
                .camera: .allowed,
                .microphone: .denied,
                .clipboard: .recentlyUsed(date),
                .screenRecording: .notDetermined,
                .accessibility: .inactive,
                .network: .inactive,
            ],
            events: []
        ))

        XCTAssertEqual(state.statusRows.map(\.category), PrivacyPulseCategory.allCases)
        XCTAssertEqual(state.statusRows.map(\.label), [
            "Allowed",
            "Denied",
            "Recently Used",
            "Not Determined",
            "Inactive",
            "Inactive",
        ])
        XCTAssertEqual(state.emptyText, "No Atlas privacy access recorded.")
    }

    func testPanelStateMapsRecentEventRowsWithoutSensitivePayloadInspection() {
        let event = PrivacyPulseEvent(
            id: UUID(),
            category: .clipboard,
            title: "Clipboard Write",
            detail: "Screenshot copied PNG data to the pasteboard",
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let state = PrivacyPulsePanelState(snapshot: PrivacyPulseSnapshot(
            statuses: [:],
            events: [event]
        ))

        XCTAssertNil(state.emptyText)
        XCTAssertEqual(state.eventRows, [
            PrivacyPulseEventRowState(
                title: "Clipboard Write",
                category: "Clipboard",
                detail: "Screenshot copied PNG data to the pasteboard"
            )
        ])
    }
}
