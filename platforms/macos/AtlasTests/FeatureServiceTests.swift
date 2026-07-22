import XCTest
@testable import Atlas

@MainActor
final class FeatureServiceTests: XCTestCase {
    func testListFeaturesReturnsInjectedFeatures() throws {
        let expected = [
            AtlasFeature(name: "monitoring", isEnabled: true),
            AtlasFeature(name: "screenshot", isEnabled: false)
        ]
        let service = FeatureService(
            listFeatures: { expected },
            toggleFeature: { _, _ in false }
        )

        let features = try service.listFeatures()

        XCTAssertEqual(features, expected)
    }

    func testToggleFeatureReceivesArgumentsAndReturnsInjectedResult() throws {
        var receivedName: String?
        var receivedEnabled: Bool?
        let service = FeatureService(
            listFeatures: { [] },
            toggleFeature: { name, enabled in
                receivedName = name
                receivedEnabled = enabled
                return true
            }
        )

        let result = try service.toggleFeature(name: "monitoring", enabled: true)

        XCTAssertEqual(receivedName, "monitoring")
        XCTAssertEqual(receivedEnabled, true)
        XCTAssertTrue(result)
    }

    func testListFeaturesPropagatesInjectedError() {
        let service = FeatureService(
            listFeatures: { throw FeatureServiceTestError.denied },
            toggleFeature: { _, _ in false }
        )

        XCTAssertThrowsError(try service.listFeatures()) { error in
            XCTAssertEqual(error.localizedDescription, "denied")
        }
    }

    func testFeatureStateStoreRoundTripsStates() {
        let suiteName = "FeatureServiceTests.featureStateStore"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeatureStateStore(defaults: defaults)

        store.saveFeatureStates(["monitoring": true, "screenshot": false])

        XCTAssertEqual(store.loadFeatureStates(), ["monitoring": true, "screenshot": false])
    }

    func testSynchronizerRestoresAllowedStatesAndDisablesDeniedStates() throws {
        let features = [
            AtlasFeature(name: "monitoring", isEnabled: false),
            AtlasFeature(name: "window-manager", isEnabled: true),
        ]
        var toggles: [String: Bool] = [:]

        let restored = try FeatureStateSynchronizer.restore(
            features: features,
            storedStates: ["monitoring": true, "window-manager": true],
            isAvailable: { $0 != "window-manager" },
            toggle: { name, enabled in
                toggles[name] = enabled
                return true
            }
        )

        XCTAssertEqual(restored.map(\.isEnabled), [true, false])
        XCTAssertEqual(toggles, ["monitoring": true, "window-manager": false])
    }
}

private enum FeatureServiceTestError: LocalizedError {
    case denied

    var errorDescription: String? {
        switch self {
        case .denied:
            return "denied"
        }
    }
}
