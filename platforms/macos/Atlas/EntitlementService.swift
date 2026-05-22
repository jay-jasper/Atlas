import Foundation

protocol EntitlementProviding {
    func currentEntitlement() -> LocalEntitlementState
}

struct LocalEntitlementProvider: EntitlementProviding {
    private enum Keys {
        static let edition = "atlas.localEdition"
    }

    private let defaults: UserDefaults
    private let bundledEdition: AtlasEdition

    init(defaults: UserDefaults = .standard, bundledEdition: AtlasEdition = .free) {
        self.defaults = defaults
        self.bundledEdition = bundledEdition
    }

    func currentEntitlement() -> LocalEntitlementState {
        if let rawEdition = defaults.string(forKey: Keys.edition),
           let edition = AtlasEdition(rawValue: rawEdition) {
            return LocalEntitlementState(
                edition: edition,
                source: .localOverride,
                note: "Using local edition override."
            )
        }

        return LocalEntitlementState(
            edition: bundledEdition,
            source: .bundled,
            note: "Using bundled local edition."
        )
    }

    func saveLocalOverride(_ edition: AtlasEdition) {
        defaults.set(edition.rawValue, forKey: Keys.edition)
    }

    func clearLocalOverride() {
        defaults.removeObject(forKey: Keys.edition)
    }
}

final class EntitlementService {
    private let provider: EntitlementProviding
    private let packageForFeature: (String) -> EditionFeaturePackage

    init(
        provider: EntitlementProviding,
        packageForFeature: @escaping (String) -> EditionFeaturePackage = EditionCatalog.package(for:)
    ) {
        self.provider = provider
        self.packageForFeature = packageForFeature
    }

    func currentState() -> LocalEntitlementState {
        provider.currentEntitlement()
    }

    func availability(for featureName: String) -> FeatureAvailability {
        let state = provider.currentEntitlement()
        let package = packageForFeature(featureName)

        guard package.isIncluded(in: state.edition) else {
            return .unavailable(
                requiredEdition: package.requiredEdition,
                label: "\(package.requiredEdition.title) required"
            )
        }

        return .available(label: package.label)
    }

    func applyAvailability(to features: [AtlasFeature]) -> [AtlasFeature] {
        features.map { feature in
            feature.withAvailability(availability(for: feature.name))
        }
    }
}
