import Foundation

protocol FeatureProviding {
    func listFeatures() throws -> [AtlasFeature]
    func toggleFeature(name: String, enabled: Bool) throws -> Bool
    func configureEntitlement(_ edition: AtlasEdition) throws
}

struct FeatureService: FeatureProviding {
    private let listFeaturesHandler: () throws -> [AtlasFeature]
    private let toggleFeatureHandler: (String, Bool) throws -> Bool
    private let configureEntitlementHandler: (AtlasEdition) throws -> Void

    init(
        listFeatures: @escaping () throws -> [AtlasFeature],
        toggleFeature: @escaping (String, Bool) throws -> Bool,
        configureEntitlement: @escaping (AtlasEdition) throws -> Void = { _ in }
    ) {
        self.listFeaturesHandler = listFeatures
        self.toggleFeatureHandler = toggleFeature
        self.configureEntitlementHandler = configureEntitlement
    }

    func listFeatures() throws -> [AtlasFeature] {
        try listFeaturesHandler()
    }

    func toggleFeature(name: String, enabled: Bool) throws -> Bool {
        try toggleFeatureHandler(name, enabled)
    }

    func configureEntitlement(_ edition: AtlasEdition) throws {
        try configureEntitlementHandler(edition)
    }
}

extension FeatureService {
    static let live = FeatureService(
        listFeatures: {
            try Atlas.listFeatures().map(AtlasFeatureMapper.map)
        },
        toggleFeature: { name, enabled in
            try Atlas.toggleFeature(name: name, enabled: enabled)
        },
        configureEntitlement: { edition in
            try Atlas.configureEntitlement(edition: edition.coreEdition)
        }
    )
}

protocol FeatureStateStoring {
    func loadFeatureStates() -> [String: Bool]
    func saveFeatureStates(_ states: [String: Bool])
}

struct FeatureStateStore: FeatureStateStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "atlas.featureStates.v1") {
        self.defaults = defaults
        self.key = key
    }

    func loadFeatureStates() -> [String: Bool] {
        guard let values = defaults.dictionary(forKey: key) else { return [:] }
        return values.reduce(into: [:]) { result, entry in
            if let value = entry.value as? Bool {
                result[entry.key] = value
            }
        }
    }

    func saveFeatureStates(_ states: [String: Bool]) {
        defaults.set(states, forKey: key)
    }
}

enum FeatureStateSynchronizer {
    static func restore(
        features: [AtlasFeature],
        storedStates: [String: Bool],
        isAvailable: (String) -> Bool,
        toggle: (String, Bool) throws -> Bool
    ) throws -> [AtlasFeature] {
        try features.map { feature in
            let requested = storedStates[feature.name] ?? feature.isEnabled
            let target = requested && isAvailable(feature.name)
            guard target != feature.isEnabled else { return feature }
            guard try toggle(feature.name, target) else { return feature }
            return AtlasFeature(name: feature.name, isEnabled: target, availability: feature.availability)
        }
    }
}
