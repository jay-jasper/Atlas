protocol FeatureProviding {
    func listFeatures() throws -> [AtlasFeature]
    func toggleFeature(name: String, enabled: Bool) throws -> Bool
}

struct FeatureService: FeatureProviding {
    private let listFeaturesHandler: () throws -> [AtlasFeature]
    private let toggleFeatureHandler: (String, Bool) throws -> Bool

    init(
        listFeatures: @escaping () throws -> [AtlasFeature],
        toggleFeature: @escaping (String, Bool) throws -> Bool
    ) {
        self.listFeaturesHandler = listFeatures
        self.toggleFeatureHandler = toggleFeature
    }

    func listFeatures() throws -> [AtlasFeature] {
        try listFeaturesHandler()
    }

    func toggleFeature(name: String, enabled: Bool) throws -> Bool {
        try toggleFeatureHandler(name, enabled)
    }
}

extension FeatureService {
    static let live = FeatureService(
        listFeatures: {
            try Atlas.listFeatures().map(AtlasFeatureMapper.map)
        },
        toggleFeature: { name, enabled in
            try Atlas.toggleFeature(name: name, enabled: enabled)
        }
    )
}
