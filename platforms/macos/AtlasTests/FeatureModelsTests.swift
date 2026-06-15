import XCTest
@testable import Atlas

@MainActor
final class FeatureModelsTests: XCTestCase {
    func testMapsAutomationFeatureTitle() {
        let entry = FeatureEntry(name: "automation", status: .disabled)

        let feature = AtlasFeatureMapper.map(entry)

        XCTAssertEqual(feature, AtlasFeature(name: "automation", isEnabled: false))
        XCTAssertEqual(feature.title, "Automation")
    }

    func testMapsEnabledFeatureEntry() {
        let entry = FeatureEntry(name: "monitoring", status: .enabled)

        let feature = AtlasFeatureMapper.map(entry)

        XCTAssertEqual(feature, AtlasFeature(name: "monitoring", isEnabled: true))
        XCTAssertEqual(feature.id, "monitoring")
        XCTAssertEqual(feature.title, "Monitoring")
    }

    func testMapsDisabledFeatureEntry() {
        let entry = FeatureEntry(name: "screenshot", status: .disabled)

        let feature = AtlasFeatureMapper.map(entry)

        XCTAssertEqual(feature, AtlasFeature(name: "screenshot", isEnabled: false))
        XCTAssertEqual(feature.title, "Screenshot")
    }

    func testFormatsUnknownFeatureName() {
        let feature = AtlasFeature(name: "local-cache", isEnabled: false)

        XCTAssertEqual(feature.title, "Local Cache")
    }

    func testWindowManagerFeatureUsesAtlasModuleTitle() {
        let feature = AtlasFeature(name: "window-manager", isEnabled: false)

        XCTAssertEqual(feature.title, "Window Manager")
    }

    func testMapsTokenBarTitle() {
        let feature = AtlasFeature(name: "tokenbar", isEnabled: false)

        XCTAssertEqual(feature.title, "TokenBar")
    }

    func testMapsAILoadTitle() {
        let feature = AtlasFeature(name: "ai-load-monitor", isEnabled: false)

        XCTAssertEqual(feature.title, "AI Load")
    }

    func testMapsScratchpadFeatureTitle() {
        let entry = FeatureEntry(name: "scratchpad", status: .disabled)

        let feature = AtlasFeatureMapper.map(entry)

        XCTAssertEqual(feature, AtlasFeature(name: "scratchpad", isEnabled: false))
        XCTAssertEqual(feature.title, "Scratchpad")
    }

    func testMapsSkillsTitle() {
        let feature = AtlasFeature(name: "skills", isEnabled: false)

        XCTAssertEqual(feature.title, "AI Skills")
    }

    func testClipboardFeatureUsesProductTitle() {
        let feature = AtlasFeature(name: "clipboard", isEnabled: false)

        XCTAssertEqual(feature.title, "Clipboard History")
    }

    func testPrivacyFeatureTitleUsesProductName() {
        let feature = AtlasFeature(name: "privacy", isEnabled: false)

        XCTAssertEqual(feature.title, "Privacy Pulse")
    }

    func testMapsSystemUtilitiesTitle() {
        let feature = AtlasFeature(name: "system-utilities", isEnabled: false)

        XCTAssertEqual(feature.title, "System Utilities")
    }

    func testFeatureAvailabilityDefaultsToAvailable() {
        let feature = AtlasFeature(name: "monitoring", isEnabled: true)

        XCTAssertTrue(feature.isAvailable)
        XCTAssertNil(feature.availabilityLabel)
    }

    func testFeatureAvailabilityMetadataIsExposed() {
        let feature = AtlasFeature(
            name: "window-manager",
            isEnabled: false,
            availability: .unavailable(requiredEdition: .pro, label: "Pro required")
        )

        XCTAssertFalse(feature.isAvailable)
        XCTAssertEqual(feature.availabilityLabel, "Pro required")
    }
}
