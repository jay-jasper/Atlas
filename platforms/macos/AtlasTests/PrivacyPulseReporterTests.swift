import XCTest
@testable import Atlas

private final class SpyLogger: PrivacyPulseAccessLogging {
    var events: [(category: PrivacyPulseCategory, title: String)] = []
    func record(category: PrivacyPulseCategory, title: String, detail: String) {
        events.append((category, title))
    }
}

@MainActor
final class PrivacyPulseReporterTests: XCTestCase {
    func testReportsMicKeyboardNetworkCategories() {
        let reporter = PrivacyPulseReporter()
        let spy = SpyLogger()
        reporter.logger = spy

        reporter.microphone("Audio Recording")
        reporter.keyboard("Keyboard Display")
        reporter.network("LAN Transfer", detail: "advertising")

        XCTAssertEqual(spy.events.map(\.category), [.microphone, .accessibility, .network])
        XCTAssertTrue(spy.events[0].title.contains("Audio Recording"))
        XCTAssertTrue(spy.events[2].title.contains("LAN Transfer"))
    }

    func testNetworkCategoryHasTitle() {
        XCTAssertEqual(PrivacyPulseCategory.network.title, "Network")
        XCTAssertTrue(PrivacyPulseCategory.allCases.contains(.network))
    }
}
