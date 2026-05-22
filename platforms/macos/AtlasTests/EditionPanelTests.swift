import XCTest
@testable import Atlas

final class EditionPanelTests: XCTestCase {
    func testStateLabelsBundledEdition() {
        let state = EditionPanelState(entitlement: LocalEntitlementState(
            edition: .free,
            source: .bundled,
            note: "Using bundled local edition."
        ))

        XCTAssertEqual(state.title, "Free Edition")
        XCTAssertEqual(state.subtitle, "Core local utilities")
        XCTAssertEqual(state.sourceLabel, "Bundled")
    }

    func testStateLabelsFallbackEdition() {
        let state = EditionPanelState(entitlement: .fallback)

        XCTAssertEqual(state.title, "Free Edition")
        XCTAssertEqual(state.sourceLabel, "Fallback")
    }
}
