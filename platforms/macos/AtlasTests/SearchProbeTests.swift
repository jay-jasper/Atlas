import XCTest
@testable import Atlas

@MainActor
final class SearchProbeTests: XCTestCase {
    func testAntiDoesNotMatchCaptureCommands() {
        let provider = AtlasCommandProvider(
            onCaptureDesktop: {}, onCaptureArea: {}, onCaptureWindow: {}, onOpenSettings: {}
        )
        let adapter = CommandProviderAdapter(provider: provider, sourceID: "atlas")
        let sections = LauncherSectionBuilder.build(
            query: "anti", sources: [adapter], favorites: [], records: [:]
        )
        XCTAssertTrue(sections.isEmpty, "got: \(sections.flatMap(\.items).map(\.title))")
    }
}
