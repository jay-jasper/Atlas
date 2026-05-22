import SwiftUI

struct TokenBarSettingsPanel: View {
    @State private var provider: TokenBarProvider
    @State private var displayName: String
    @State private var endpoint: String
    @State private var apiKey: String
    @State private var defaultModel: String

    let onSave: (TokenBarProviderConfiguration) -> Void
    let onClear: () -> Void

    init(
        configuration: TokenBarProviderConfiguration?,
        onSave: @escaping (TokenBarProviderConfiguration) -> Void,
        onClear: @escaping () -> Void
    ) {
        _provider = State(initialValue: configuration?.provider ?? .openAI)
        _displayName = State(initialValue: configuration?.displayName ?? "OpenAI")
        _endpoint = State(initialValue: configuration?.endpoint.absoluteString ?? "https://api.openai.com")
        _apiKey = State(initialValue: configuration?.apiKey ?? "")
        _defaultModel = State(initialValue: configuration?.defaultModel ?? "gpt-4.1-mini")
        self.onSave = onSave
        self.onClear = onClear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TokenBar")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("Provider", selection: $provider) {
                ForEach(TokenBarProvider.allCases, id: \.self) { provider in
                    Text(provider.title).tag(provider)
                }
            }

            TextField("Display Name", text: $displayName)
            TextField("Base URL", text: $endpoint)
            SecureField("API Key", text: $apiKey)
            TextField("Default Model", text: $defaultModel)

            HStack {
                Button("Save TokenBar Settings") {
                    guard let url = URL(string: endpoint),
                          !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else {
                        return
                    }

                    onSave(TokenBarProviderConfiguration(
                        provider: provider,
                        displayName: displayName,
                        endpoint: url,
                        apiKey: apiKey,
                        defaultModel: defaultModel
                    ))
                }

                Button("Clear TokenBar Settings") {
                    provider = .openAI
                    displayName = "OpenAI"
                    endpoint = "https://api.openai.com"
                    apiKey = ""
                    defaultModel = "gpt-4.1-mini"
                    onClear()
                }
            }
        }
    }
}
