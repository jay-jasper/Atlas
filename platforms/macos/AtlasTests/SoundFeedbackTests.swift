import XCTest
@testable import Atlas

@MainActor
final class SoundFeedbackMappingTests: XCTestCase {
    func testDefaultsCoverAllEvents() {
        for event in SoundEvent.allCases {
            XCTAssertNotNil(SoundFeedbackMapping.soundName(for: event))
        }
    }

    func testOverrideTakesPrecedence() {
        XCTAssertEqual(
            SoundFeedbackMapping.soundName(for: .appSwitch, overrides: [.appSwitch: "Funk"]),
            "Funk"
        )
    }
}

private final class SpyPlayer: SoundPlaying {
    private(set) var played: [String] = []
    func play(named name: String) { played.append(name) }
}

@MainActor
final class SoundFeedbackServiceTests: XCTestCase {
    func testFiresWhenEnabled() {
        let spy = SpyPlayer()
        let service = SoundFeedbackService(player: spy)
        service.isEnabled = true
        service.fire(.screenshotCaptured)
        XCTAssertEqual(spy.played, ["Grab"])
    }

    func testDoesNotFireWhenGloballyDisabled() {
        let spy = SpyPlayer()
        let service = SoundFeedbackService(player: spy)
        service.isEnabled = false
        service.fire(.appSwitch)
        XCTAssertTrue(spy.played.isEmpty)
    }

    func testDoesNotFireWhenEventToggledOff() {
        let spy = SpyPlayer()
        let service = SoundFeedbackService(player: spy)
        service.isEnabled = true
        service.toggle(.appSwitch) // turn off
        service.fire(.appSwitch)
        XCTAssertTrue(spy.played.isEmpty)
    }
}
