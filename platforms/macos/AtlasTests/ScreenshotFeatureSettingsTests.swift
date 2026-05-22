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
        XCTAssertTrue(settings.isEnabled(.scrollingCapture))
        XCTAssertTrue(settings.isEnabled(.gifRecording))
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
        XCTAssertTrue(loaded.isEnabled(.scrollingCapture))
        XCTAssertTrue(loaded.isEnabled(.gifRecording))
        XCTAssertTrue(loaded.isEnabled(.annotations))
        XCTAssertTrue(loaded.isEnabled(.pinning))
        XCTAssertTrue(loaded.isEnabled(.translation))
    }

    func testCapabilitiesMapSettingsToCaptureAndEditorSurfaces() {
        var settings = ScreenshotFeatureSettings.defaultEnabled
        settings.setEnabled(false, for: .areaCapture)
        settings.setEnabled(false, for: .scrollingCapture)
        settings.setEnabled(false, for: .gifRecording)
        settings.setEnabled(false, for: .annotations)
        settings.setEnabled(false, for: .pinning)
        settings.setEnabled(false, for: .translation)

        XCTAssertTrue(settings.captureCapabilities.desktop)
        XCTAssertTrue(settings.captureCapabilities.window)
        XCTAssertFalse(settings.captureCapabilities.area)
        XCTAssertFalse(settings.captureCapabilities.scrolling)
        XCTAssertFalse(settings.captureCapabilities.gifRecording)
        XCTAssertFalse(settings.editorCapabilities.annotations)
        XCTAssertFalse(settings.editorCapabilities.pinning)
        XCTAssertTrue(settings.editorCapabilities.ocr)
        XCTAssertFalse(settings.editorCapabilities.translation)
    }

    func testDefaultSettingsEnableScrollingCapture() {
        let settings = ScreenshotFeatureSettings.defaultEnabled

        XCTAssertTrue(settings.isEnabled(.scrollingCapture))
        XCTAssertTrue(settings.captureCapabilities.scrolling)
    }

    func testScrollingCaptureCanBeDisabled() {
        var settings = ScreenshotFeatureSettings.defaultEnabled
        settings.setEnabled(false, for: .scrollingCapture)

        XCTAssertFalse(settings.isEnabled(.scrollingCapture))
        XCTAssertFalse(settings.captureCapabilities.scrolling)
    }

    func testDefaultSettingsEnableGIFRecording() {
        let settings = ScreenshotFeatureSettings.defaultEnabled

        XCTAssertTrue(settings.isEnabled(.gifRecording))
        XCTAssertTrue(settings.captureCapabilities.gifRecording)
    }

    func testGIFRecordingCanBeDisabled() {
        var settings = ScreenshotFeatureSettings.defaultEnabled
        settings.setEnabled(false, for: .gifRecording)

        XCTAssertFalse(settings.isEnabled(.gifRecording))
        XCTAssertFalse(settings.captureCapabilities.gifRecording)
    }

    func testFeatureMetadataIsStable() {
        XCTAssertEqual(ScreenshotSubfeature.allCases.map(\.rawValue), [
            "desktop-capture",
            "window-capture",
            "area-capture",
            "scrolling-capture",
            "gif-recording",
            "annotations",
            "pinning",
            "ocr",
            "translation",
        ])

        XCTAssertEqual(ScreenshotSubfeature.desktopCapture.title, "Desktop Capture")
        XCTAssertEqual(ScreenshotSubfeature.windowCapture.systemImage, "macwindow")
        XCTAssertEqual(ScreenshotSubfeature.scrollingCapture.title, "Scrolling Capture")
        XCTAssertEqual(ScreenshotSubfeature.gifRecording.systemImage, "record.circle")
        XCTAssertEqual(ScreenshotSubfeature.translation.title, "Translation")
    }
}
