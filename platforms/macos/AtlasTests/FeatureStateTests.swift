import XCTest
@testable import Atlas

@MainActor
final class FeatureStateTests: XCTestCase {
    func testEnabledMapUsesActualFeatureStates() {
        let features = [
            AtlasFeature(name: "monitoring", isEnabled: true),
            AtlasFeature(name: "screenshot", isEnabled: false)
        ]

        let enabledMap = FeatureStateReducer.enabledMap(from: features)

        XCTAssertEqual(enabledMap["monitoring"], true)
        XCTAssertEqual(enabledMap["screenshot"], false)
    }

    func testRefreshedFeaturesChangesOnlyNamedFeature() {
        let features = [
            AtlasFeature(name: "monitoring", isEnabled: false),
            AtlasFeature(name: "screenshot", isEnabled: true),
            AtlasFeature(name: "window-manager", isEnabled: false)
        ]

        let refreshedFeatures = FeatureStateReducer.refreshedFeatures(
            features,
            featureName: "monitoring",
            enabled: true
        )

        XCTAssertEqual(
            refreshedFeatures,
            [
                AtlasFeature(name: "monitoring", isEnabled: true),
                AtlasFeature(name: "screenshot", isEnabled: true),
                AtlasFeature(name: "window-manager", isEnabled: false)
            ]
        )
    }

    func testRolledBackValueInvertsRequestedState() {
        XCTAssertFalse(FeatureStateReducer.rolledBackValue(forRequestedEnabled: true))
        XCTAssertTrue(FeatureStateReducer.rolledBackValue(forRequestedEnabled: false))
    }
}
