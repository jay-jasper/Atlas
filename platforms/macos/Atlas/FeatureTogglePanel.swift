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
                    get: { feature.isAvailable && enabledFeatures[feature.name, default: feature.isEnabled] },
                    set: { enabled in
                        guard feature.isAvailable else { return }
                        enabledFeatures[feature.name] = enabled
                        onFeatureChanged(feature.name, enabled)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(feature.title)
                            if let label = feature.availabilityLabel {
                                Text(label)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(feature.isAvailable ? Color.secondary.opacity(0.12) : Color.orange.opacity(0.16))
                                    .foregroundColor(feature.isAvailable ? .secondary : .orange)
                                    .cornerRadius(4)
                            }
                        }
                        Text(feature.name).font(.caption).foregroundColor(.secondary)
                    }
                }
                .disabled(!feature.isAvailable)
            }
        }
    }

    private var enabledCount: Int {
        features.filter { feature in
            feature.isAvailable && enabledFeatures[feature.name, default: feature.isEnabled]
        }.count
    }
}
