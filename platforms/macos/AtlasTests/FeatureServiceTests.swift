import XCTest
@testable import Atlas

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
