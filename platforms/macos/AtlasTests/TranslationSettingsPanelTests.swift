import XCTest
@testable import Atlas

@MainActor
final class TranslationSettingsPanelTests: XCTestCase {
    func testEmptyDraftStatusIsNotConfigured() {
        let state = TranslationSettingsPanelState(
            draft: .empty,
            isConfigured: false
        )

        XCTAssertEqual(state.statusText, "Translation endpoint not configured")
        XCTAssertFalse(state.canSave)
    }

    func testValidEndpointCanSave() {
        let state = TranslationSettingsPanelState(
            draft: ScreenshotTranslationSettingsDraft(
                endpoint: "https://example.com/translate",
                apiKey: "",
                model: "",
                targetLanguage: ""
            ),
            isConfigured: true
        )

        XCTAssertEqual(state.statusText, "Translation endpoint configured")
        XCTAssertTrue(state.canSave)
    }

    func testInvalidEndpointStatus() {
        let state = TranslationSettingsPanelState(
            draft: ScreenshotTranslationSettingsDraft(
                endpoint: "not a url",
                apiKey: "",
                model: "",
                targetLanguage: ""
            ),
            isConfigured: false
        )

        XCTAssertEqual(state.statusText, "Translation endpoint is invalid")
        XCTAssertFalse(state.canSave)
    }
}
