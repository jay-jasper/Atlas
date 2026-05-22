import XCTest
@testable import Atlas

final class EntitlementServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "EntitlementServiceTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testProviderUsesBundledEditionWhenNoOverrideExists() {
        let provider = LocalEntitlementProvider(defaults: defaults, bundledEdition: .community)

        XCTAssertEqual(provider.currentEntitlement(), LocalEntitlementState(
            edition: .community,
            source: .bundled,
            note: "Using bundled local edition."
        ))
    }

    func testProviderUsesLocalOverride() {
        let provider = LocalEntitlementProvider(defaults: defaults, bundledEdition: .free)

        provider.saveLocalOverride(.pro)

        XCTAssertEqual(provider.currentEntitlement().edition, .pro)
        XCTAssertEqual(provider.currentEntitlement().source, .localOverride)
    }

    func testClearLocalOverrideRestoresBundledEdition() {
        let provider = LocalEntitlementProvider(defaults: defaults, bundledEdition: .free)
        provider.saveLocalOverride(.pro)

        provider.clearLocalOverride()

        XCTAssertEqual(provider.currentEntitlement().edition, .free)
        XCTAssertEqual(provider.currentEntitlement().source, .bundled)
    }

    func testFreeEditionBlocksProPackagedFeature() {
        let service = EntitlementService(provider: StaticEntitlementProvider(state: .init(
            edition: .free,
            source: .bundled,
            note: "test"
        )))

        XCTAssertEqual(service.availability(for: "window-manager"), .unavailable(
            requiredEdition: .pro,
            label: "Pro required"
        ))
    }

    func testProEditionAllowsProPackagedFeature() {
        let service = EntitlementService(provider: StaticEntitlementProvider(state: .init(
            edition: .pro,
            source: .localOverride,
            note: "test"
        )))

        XCTAssertEqual(service.availability(for: "tokenbar"), .available(label: "Pro"))
    }

    func testUnknownFeatureFallsBackToAvailable() {
        let service = EntitlementService(provider: StaticEntitlementProvider(state: LocalEntitlementState.fallback))

        XCTAssertEqual(service.availability(for: "future-local-tool"), .available(label: "Included"))
    }

    func testApplyAvailabilityAnnotatesFeatures() {
        let service = EntitlementService(provider: StaticEntitlementProvider(state: .init(
            edition: .free,
            source: .bundled,
            note: "test"
        )))

        let features = service.applyAvailability(to: [
            AtlasFeature(name: "monitoring", isEnabled: true),
            AtlasFeature(name: "window-manager", isEnabled: false),
        ])

        XCTAssertTrue(features[0].isAvailable)
        XCTAssertEqual(features[0].availabilityLabel, "Included")
        XCTAssertFalse(features[1].isAvailable)
        XCTAssertEqual(features[1].availabilityLabel, "Pro required")
    }
}

private struct StaticEntitlementProvider: EntitlementProviding {
    let state: LocalEntitlementState

    func currentEntitlement() -> LocalEntitlementState {
        state
    }
}
