import SwiftUI

struct TranslationSettingsPanelState: Equatable {
    let draft: ScreenshotTranslationSettingsDraft
    let isConfigured: Bool

    var canSave: Bool {
        isValidEndpoint
    }

    var statusText: String {
        if draft.trimmedEndpoint.isEmpty {
            return "Translation endpoint not configured"
        }

        if !isValidEndpoint {
            return "Translation endpoint is invalid"
        }

        return isConfigured ? "Translation endpoint configured" : "Translation endpoint ready to save"
    }

    private var isValidEndpoint: Bool {
        guard let url = URL(string: draft.trimmedEndpoint),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              let host = url.host else {
            return false
        }

        let cleanedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanedHost.isEmpty
            && cleanedHost != "."
            && !cleanedHost.contains("_")
            && !cleanedHost.hasPrefix(".")
            && !cleanedHost.hasSuffix(".")
    }
}

struct TranslationSettingsPanel: View {
    @State private var draft: ScreenshotTranslationSettingsDraft
    let isConfigured: Bool
    let onSave: (ScreenshotTranslationSettingsDraft) -> Void
    let onClear: () -> Void

    init(
        draft: ScreenshotTranslationSettingsDraft,
        isConfigured: Bool,
        onSave: @escaping (ScreenshotTranslationSettingsDraft) -> Void,
        onClear: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.isConfigured = isConfigured
        self.onSave = onSave
        self.onClear = onClear
    }

    var body: some View {
        let state = TranslationSettingsPanelState(draft: draft, isConfigured: isConfigured)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Translation").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Text(state.statusText).font(.caption).foregroundColor(state.canSave || draft.trimmedEndpoint.isEmpty ? .secondary : .red)
            }

            TextField("https://example.com/translate", text: $draft.endpoint)
                .textFieldStyle(.roundedBorder)

            SecureField("API key", text: $draft.apiKey)
                .textFieldStyle(.roundedBorder)

            TextField("Model", text: $draft.model)
                .textFieldStyle(.roundedBorder)

            TextField("Target language (default: English)", text: $draft.targetLanguage)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save") {
                    onSave(draft)
                }
                .disabled(!state.canSave)

                Button("Clear") {
                    draft = .empty
                    onClear()
                }

                Spacer()
            }
        }
    }
}
