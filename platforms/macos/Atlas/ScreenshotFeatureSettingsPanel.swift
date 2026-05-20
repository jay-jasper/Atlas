import SwiftUI

struct ScreenshotFeatureSettingsPanelState: Equatable {
    let settings: ScreenshotFeatureSettings

    var enabledCount: Int {
        settings.enabledCount
    }

    var totalCount: Int {
        ScreenshotSubfeature.allCases.count
    }

    var summaryText: String {
        if enabledCount == totalCount {
            return "\(enabledCount) enabled"
        }
        return "\(enabledCount) of \(totalCount) enabled"
    }

    var hasDisabledFeatures: Bool {
        enabledCount < totalCount
    }

    static func set(
        _ enabled: Bool,
        for feature: ScreenshotSubfeature,
        in settings: inout ScreenshotFeatureSettings
    ) {
        settings.setEnabled(enabled, for: feature)
    }
}

struct ScreenshotFeatureSettingsPanel: View {
    @State private var draft: ScreenshotFeatureSettings

    let onSave: (ScreenshotFeatureSettings) -> Void

    init(settings: ScreenshotFeatureSettings, onSave: @escaping (ScreenshotFeatureSettings) -> Void) {
        _draft = State(initialValue: settings)
        self.onSave = onSave
    }

    var body: some View {
        let state = ScreenshotFeatureSettingsPanelState(settings: draft)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Screenshot Features")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(state.summaryText)
                    .font(.caption)
                    .foregroundColor(state.hasDisabledFeatures ? .orange : .secondary)
            }

            ForEach(ScreenshotSubfeature.allCases) { feature in
                Toggle(isOn: binding(for: feature)) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: feature.systemImage)
                            .frame(width: 18)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                            Text(feature.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Save") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func binding(for feature: ScreenshotSubfeature) -> Binding<Bool> {
        Binding(
            get: { draft.isEnabled(feature) },
            set: { enabled in
                ScreenshotFeatureSettingsPanelState.set(enabled, for: feature, in: &draft)
            }
        )
    }
}
