import SwiftUI

@MainActor
struct AtlasSettingsView: View {
    private let featureSettingsStore = ScreenshotFeatureSettingsStore()
    private let translationConfigStore = ScreenshotTranslationConfigurationStore()
    private let tokenBarConfigStore = TokenBarConfigurationStore()
    let paletteController: CommandPaletteController

    @State private var screenshotFeatureSettings: ScreenshotFeatureSettings = .defaultEnabled
    @State private var translationSettingsDraft: ScreenshotTranslationSettingsDraft = .empty
    @State private var isTranslationConfigured: Bool = false
    @State private var tokenBarConfiguration: TokenBarProviderConfiguration?
    @State private var featureSettingsIdentity: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenshotFeatureSettingsPanel(
                    settings: screenshotFeatureSettings,
                    onSave: saveFeatureSettings
                )
                .id(featureSettingsIdentity)

                Divider()

                TranslationSettingsPanel(
                    draft: translationSettingsDraft,
                    isConfigured: isTranslationConfigured,
                    onSave: saveTranslationSettings,
                    onClear: clearTranslationSettings
                )

                Divider()

                TokenBarSettingsPanel(
                    configuration: tokenBarConfiguration,
                    onSave: saveTokenBarSettings,
                    onClear: clearTokenBarSettings
                )

                Divider()

                commandPaletteSection

                Divider()

                AutomationSettingsView(store: CustomAutomationStore())
            }
            .padding()
        }
        .frame(width: 340)
        .onAppear { load() }
    }

    @ViewBuilder
    private var commandPaletteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command Palette")
                .font(.subheadline)
                .foregroundColor(.secondary)

            KeyRecorderView { [weak paletteController] newConfig in
                paletteController?.updateHotkey(newConfig)
            }
        }
    }

    private func load() {
        screenshotFeatureSettings = featureSettingsStore.load()
        featureSettingsIdentity = makeFeatureIdentity()
        translationSettingsDraft = translationConfigStore.settingsDraft()
        isTranslationConfigured = translationConfigStore.httpConfig() != nil
        tokenBarConfiguration = tokenBarConfigStore.load()
    }

    private func saveFeatureSettings(_ settings: ScreenshotFeatureSettings) {
        featureSettingsStore.save(settings)
        screenshotFeatureSettings = settings
        featureSettingsIdentity = makeFeatureIdentity()
    }

    private func saveTranslationSettings(_ draft: ScreenshotTranslationSettingsDraft) {
        translationConfigStore.save(draft)
        translationSettingsDraft = translationConfigStore.settingsDraft()
        isTranslationConfigured = translationConfigStore.httpConfig() != nil
    }

    private func clearTranslationSettings() {
        translationConfigStore.clear()
        translationSettingsDraft = .empty
        isTranslationConfigured = false
    }

    private func saveTokenBarSettings(_ configuration: TokenBarProviderConfiguration) {
        tokenBarConfigStore.save(configuration)
        tokenBarConfiguration = tokenBarConfigStore.load()
    }

    private func clearTokenBarSettings() {
        tokenBarConfigStore.clear()
        tokenBarConfiguration = nil
    }

    private func makeFeatureIdentity() -> String {
        ScreenshotSubfeature.allCases
            .map { screenshotFeatureSettings.isEnabled($0) ? "1" : "0" }
            .joined()
    }
}
