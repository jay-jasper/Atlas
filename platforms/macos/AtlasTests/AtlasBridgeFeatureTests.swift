import XCTest
@testable import Atlas

private extension FeatureProviding where Self == FeatureService {
    static var live: FeatureService { FeatureService.live }
}

private final class FakeFeatureProvider: FeatureProviding {
    var features = [
        AtlasFeature(name: "monitoring", isEnabled: false),
        AtlasFeature(name: "screenshot", isEnabled: true)
    ]
    var listCount = 0
    var toggledName: String?
    var toggledEnabled: Bool?
    var toggleResult = true

    func listFeatures() throws -> [AtlasFeature] {
        listCount += 1
        return features
    }

    func toggleFeature(name: String, enabled: Bool) throws -> Bool {
        toggledName = name
        toggledEnabled = enabled
        return toggleResult
    }
}

@MainActor
final class AtlasBridgeFeatureTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.featureService = .live
        super.tearDown()
    }

    func testListFeaturesUsesProvider() throws {
        let provider = FakeFeatureProvider()
        AtlasBridge.featureService = provider

        let features = try AtlasBridge.listFeatures()

        XCTAssertEqual(provider.listCount, 1)
        XCTAssertEqual(features, provider.features)
    }

    func testToggleFeatureUsesProvider() throws {
        let provider = FakeFeatureProvider()
        AtlasBridge.featureService = provider

        let result = try AtlasBridge.toggleFeature(name: "monitoring", enabled: true)

        XCTAssertEqual(provider.toggledName, "monitoring")
        XCTAssertEqual(provider.toggledEnabled, true)
        XCTAssertTrue(result)
    }

    func testToggleFeatureCanReturnFalseForUnknownFeature() throws {
        let provider = FakeFeatureProvider()
        provider.toggleResult = false
        AtlasBridge.featureService = provider

        let result = try AtlasBridge.toggleFeature(name: "unknown", enabled: true)

        XCTAssertEqual(provider.toggledName, "unknown")
        XCTAssertEqual(provider.toggledEnabled, true)
        XCTAssertFalse(result)
    }
}
