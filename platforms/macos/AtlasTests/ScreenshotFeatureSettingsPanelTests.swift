import XCTest
@testable import Atlas

final class ScreenshotFeatureSettingsPanelTests: XCTestCase {
    func testStateSummaryForAllEnabledSettings() {
        let state = ScreenshotFeatureSettingsPanelState(settings: .defaultEnabled)

        XCTAssertEqual(state.enabledCount, ScreenshotSubfeature.allCases.count)
        XCTAssertEqual(state.totalCount, ScreenshotSubfeature.allCases.count)
        XCTAssertEqual(state.summaryText, "7 enabled")
        XCTAssertFalse(state.hasDisabledFeatures)
    }

    func testStateSummaryForPartiallyDisabledSettings() {
        var settings = ScreenshotFeatureSettings.defaultEnabled
        settings.setEnabled(false, for: .ocr)
        settings.setEnabled(false, for: .translation)

        let state = ScreenshotFeatureSettingsPanelState(settings: settings)

        XCTAssertEqual(state.enabledCount, 5)
        XCTAssertEqual(state.totalCount, 7)
        XCTAssertEqual(state.summaryText, "5 of 7 enabled")
        XCTAssertTrue(state.hasDisabledFeatures)
    }

    func testBindingUpdateChangesOnlySelectedFeature() {
        var settings = ScreenshotFeatureSettings.defaultEnabled

        ScreenshotFeatureSettingsPanelState.set(false, for: .windowCapture, in: &settings)

        XCTAssertFalse(settings.isEnabled(.windowCapture))
        XCTAssertTrue(settings.isEnabled(.desktopCapture))
        XCTAssertTrue(settings.isEnabled(.areaCapture))
    }
}
