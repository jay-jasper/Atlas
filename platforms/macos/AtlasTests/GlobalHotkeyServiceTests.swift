import XCTest
@testable import Atlas

@MainActor
final class GlobalHotkeyServiceTests: XCTestCase {
    private var service: GlobalHotkeyService!

    override func setUp() {
        super.setUp()
        service = GlobalHotkeyService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testRegisteredHandlerIsStoredAndRetrievable() {
        var count = 0
        service.register(keyCode: 49, modifiers: .option) { count += 1 }
        XCTAssertEqual(service.registeredCount, 1)
    }

    func testMultipleHandlersCanBeRegistered() {
        service.register(keyCode: 49, modifiers: .option) {}
        service.register(keyCode: 21, modifiers: [.control, .shift]) {}
        XCTAssertEqual(service.registeredCount, 2)
    }

    func testCorrectHandlerFiredForMatchingKeyCode() {
        var firstCalled = false
        var secondCalled = false
        service.register(keyCode: 49, modifiers: .option) { firstCalled = true }
        service.register(keyCode: 21, modifiers: [.control, .shift]) { secondCalled = true }

        service.simulateKeyEvent(keyCode: 49, modifiers: .option)
        XCTAssertTrue(firstCalled)
        XCTAssertFalse(secondCalled)

        service.simulateKeyEvent(keyCode: 21, modifiers: [.control, .shift])
        XCTAssertTrue(secondCalled)
    }

    func testNoHandlerFiredForUnmatchedKeyCode() {
        var called = false
        service.register(keyCode: 49, modifiers: .option) { called = true }

        service.simulateKeyEvent(keyCode: 36, modifiers: .option)
        XCTAssertFalse(called)
    }

    func testModifierMismatchDoesNotFireHandler() {
        var called = false
        service.register(keyCode: 49, modifiers: .option) { called = true }

        service.simulateKeyEvent(keyCode: 49, modifiers: .command)
        XCTAssertFalse(called)
    }

    func testLegacyAreaCaptureHandlerStillWorks() {
        var called = false
        service.onAreaCapture = { called = true }

        service.simulateKeyEvent(keyCode: 21, modifiers: [.control, .shift])
        XCTAssertTrue(called)
    }

    func testAccessibilityRequestLogsCheckThroughInjectedBoundary() {
        let logger = FakeHotkeyPrivacyPulseAccessLogger()
        var promptCount = 0
        service = GlobalHotkeyService(
            accessLogger: logger,
            isProcessTrusted: { false },
            requestTrustWithPrompt: { promptCount += 1 }
        )

        service.requestAccessibilityIfNeeded()

        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(logger.events.map(\.title), ["Accessibility Check"])
        XCTAssertEqual(logger.events.first?.category, .accessibility)
    }
}

private final class FakeHotkeyPrivacyPulseAccessLogger: PrivacyPulseAccessLogging {
    struct Event: Equatable {
        let category: PrivacyPulseCategory
        let title: String
        let detail: String
    }

    private(set) var events: [Event] = []

    func record(category: PrivacyPulseCategory, title: String, detail: String) {
        events.append(Event(category: category, title: title, detail: detail))
    }
}
