import SwiftUI

struct FeatureCenterPanel: View {
    let features: [AtlasFeature]
    @Binding var enabledFeatures: [String: Bool]
    let onFeatureChanged: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Feature Center").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Text("\(enabledCount) enabled").font(.caption).foregroundColor(.secondary)
            }

            ForEach(features) { feature in
                Toggle(isOn: Binding(
                    get: { enabledFeatures[feature.name, default: feature.isEnabled] },
                    set: { enabled in
                        enabledFeatures[feature.name] = enabled
                        onFeatureChanged(feature.name, enabled)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                        Text(feature.name).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var enabledCount: Int {
        features.filter { feature in
            enabledFeatures[feature.name, default: feature.isEnabled]
        }.count
    }
}
