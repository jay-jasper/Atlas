enum FeatureStateReducer {
    static func enabledMap(from features: [AtlasFeature]) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: features.map { ($0.name, $0.isEnabled) })
    }

    static func refreshedFeatures(
        _ features: [AtlasFeature],
        featureName: String,
        enabled: Bool
    ) -> [AtlasFeature] {
        features.map { feature in
            guard feature.name == featureName else { return feature }
            return AtlasFeature(name: feature.name, isEnabled: enabled)
        }
    }

    static func rolledBackValue(forRequestedEnabled enabled: Bool) -> Bool {
        !enabled
    }
}
