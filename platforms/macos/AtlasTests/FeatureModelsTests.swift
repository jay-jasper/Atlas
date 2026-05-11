import XCTest
@testable import Atlas

final class FeatureModelsTests: XCTestCase {
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
        let feature = AtlasFeature(name: "window-manager", isEnabled: false)

        XCTAssertEqual(feature.title, "Window Manager")
    }
}
