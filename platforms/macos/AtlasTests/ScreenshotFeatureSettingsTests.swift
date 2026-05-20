import XCTest
@testable import Atlas

final class ScreenshotFeatureSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ScreenshotFeatureSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultSettingsEnableEveryScreenshotFeature() {
        let settings = ScreenshotFeatureSettings.defaultEnabled

        XCTAssertTrue(settings.isEnabled(.desktopCapture))
        XCTAssertTrue(settings.isEnabled(.windowCapture))
        XCTAssertTrue(settings.isEnabled(.areaCapture))
        XCTAssertTrue(settings.isEnabled(.annotations))
        XCTAssertTrue(settings.isEnabled(.pinning))
        XCTAssertTrue(settings.isEnabled(.ocr))
        XCTAssertTrue(settings.isEnabled(.translation))
        XCTAssertEqual(settings.enabledCount, ScreenshotSubfeature.allCases.count)
    }

    func testStoreReturnsDefaultsWhenNothingWasSaved() {
        let store = ScreenshotFeatureSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .defaultEnabled)
    }

    func testStoreSavesAndLoadsDisabledFeatures() {
        let store = ScreenshotFeatureSettingsStore(defaults: defaults)
        var settings = ScreenshotFeatureSettings.defaultEnabled
        settings.setEnabled(false, for: .windowCapture)
        settings.setEnabled(false, for: .translation)

        store.save(settings)

        let loaded = store.load()
        XCTAssertFalse(loaded.isEnabled(.windowCapture))
        XCTAssertFalse(loaded.isEnabled(.translation))
        XCTAssertTrue(loaded.isEnabled(.desktopCapture))
        XCTAssertTrue(loaded.isEnabled(.ocr))
    }

    func testStoreTreatsMissingFeatureKeysAsEnabled() {
        defaults.set(false, forKey: "screenshot.subfeature.ocr.enabled")

        let loaded = ScreenshotFeatureSettingsStore(defaults: defaults).load()

        XCTAssertFalse(loaded.isEnabled(.ocr))
        XCTAssertTrue(loaded.isEnabled(.desktopCapture))
        XCTAssertTrue(loaded.isEnabled(.windowCapture))
        XCTAssertTrue(loaded.isEnabled(.areaCapture))
        XCTAssertTrue(loaded.isEnabled(.annotations))
        XCTAssertTrue(loaded.isEnabled(.pinning))
        XCTAssertTrue(loaded.isEnabled(.translation))
    }

    func testCapabilitiesMapSettingsToCaptureAndEditorSurfaces() {
        var settings = ScreenshotFeatureSettings.defaultEnabled
        settings.setEnabled(false, for: .areaCapture)
        settings.setEnabled(false, for: .annotations)
        settings.setEnabled(false, for: .pinning)
        settings.setEnabled(false, for: .translation)

        XCTAssertTrue(settings.captureCapabilities.desktop)
        XCTAssertTrue(settings.captureCapabilities.window)
        XCTAssertFalse(settings.captureCapabilities.area)
        XCTAssertFalse(settings.editorCapabilities.annotations)
        XCTAssertFalse(settings.editorCapabilities.pinning)
        XCTAssertTrue(settings.editorCapabilities.ocr)
        XCTAssertFalse(settings.editorCapabilities.translation)
    }

    func testFeatureMetadataIsStable() {
        XCTAssertEqual(ScreenshotSubfeature.allCases.map(\.rawValue), [
            "desktop-capture",
            "window-capture",
            "area-capture",
            "annotations",
            "pinning",
            "ocr",
            "translation",
        ])

        XCTAssertEqual(ScreenshotSubfeature.desktopCapture.title, "Desktop Capture")
        XCTAssertEqual(ScreenshotSubfeature.windowCapture.systemImage, "macwindow")
        XCTAssertEqual(ScreenshotSubfeature.translation.title, "Translation")
    }
}
