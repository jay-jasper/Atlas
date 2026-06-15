import XCTest
@testable import Atlas

@MainActor
final class EditionModelsTests: XCTestCase {
    func testEditionMetadataIsStable() {
        XCTAssertEqual(AtlasEdition.free.title, "Free")
        XCTAssertEqual(AtlasEdition.pro.title, "Pro")
        XCTAssertEqual(AtlasEdition.community.title, "Community")
        XCTAssertEqual(AtlasEdition.free.subtitle, "Core local utilities")
        XCTAssertEqual(AtlasEdition.pro.subtitle, "Advanced local productivity modules")
        XCTAssertEqual(AtlasEdition.community.subtitle, "Community build with local-only access")
    }

    func testKnownCoreFeaturesAreIncludedForFreeEdition() {
        XCTAssertTrue(EditionCatalog.package(for: "monitoring").isIncluded(in: .free))
        XCTAssertTrue(EditionCatalog.package(for: "screenshot").isIncluded(in: .free))
    }

    func testKnownProFeaturesAreNotIncludedForFreeEdition() {
        XCTAssertFalse(EditionCatalog.package(for: "tokenbar").isIncluded(in: .free))
        XCTAssertFalse(EditionCatalog.package(for: "window-manager").isIncluded(in: .free))
        XCTAssertFalse(EditionCatalog.package(for: "skills").isIncluded(in: .free))
    }

    func testUnknownFeatureDefaultsToIncludedToAvoidAccidentalPaywalling() {
        let package = EditionCatalog.package(for: "future-local-tool")

        XCTAssertEqual(package.label, "Included")
        XCTAssertTrue(package.isIncluded(in: .free))
        XCTAssertTrue(package.isIncluded(in: .pro))
        XCTAssertTrue(package.isIncluded(in: .community))
    }

    func testAvailabilityLabelsExposeRequiredEdition() {
        let availability = FeatureAvailability.unavailable(requiredEdition: .pro, label: "Pro required")

        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(availability.displayLabel, "Pro required")
    }
}
