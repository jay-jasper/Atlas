import SwiftUI

/// AI 服务配置中心:Provider CRUD + API Key(Keychain 密封)+ 连通性测试。
struct AIProviderSettingsView: View {
    @ObservedObject var bridge: AIChatBridge
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var name = ""
    @State private var baseURL = "https://api.openai.com/v1"
    @State private var model = "gpt-4o-mini"
    @State private var apiKey = ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        HStack(spacing: 0) {
            providerList
                .frame(width: 180)
            Divider()
            form
                .frame(minWidth: 360)
        }
        .frame(width: 620, height: 420)
    }

    private var providerList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(bridge.providers, id: \.id) { provider in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name).font(.callout)
                        Text(provider.model).font(.caption2).foregroundColor(.secondary)
                    }
                    .tag(provider.id)
                }
            }
            .onChange(of: selectedID) { id in
                if let provider = bridge.providers.first(where: { $0.id == id }) {
                    name = provider.name
                    baseURL = provider.baseUrl
                    model = provider.model
                    apiKey = bridge.vault.key(providerID: provider.id) ?? ""
                    testResult = nil
                }
            }

            Divider()
            HStack {
                Button {
                    selectedID = nil
                    name = ""
                    baseURL = "https://api.openai.com/v1"
                    model = "gpt-4o-mini"
                    apiKey = ""
                    testResult = nil
                } label: { Image(systemName: "plus") }
                Button {
                    if let id = selectedID { bridge.deleteProvider(id); selectedID = nil }
                } label: { Image(systemName: "minus") }
                .disabled(selectedID == nil)
                Spacer()
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedID == nil ? "新增 Provider" : "编辑 Provider")
                .font(.headline)

            TextField("名称(如 OpenAI)", text: $name)
            TextField("Base URL", text: $baseURL)
            TextField("模型(如 gpt-4o-mini)", text: $model)
            SecureField("API Key", text: $apiKey)

            HStack(spacing: 10) {
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || baseURL.isEmpty || model.isEmpty)

                Button {
                    testConnectivity()
                } label: {
                    if isTesting { ProgressView().controlSize(.small) } else { Text("测试连通性") }
                }
                .disabled(isTesting || baseURL.isEmpty || apiKey.isEmpty)

                Spacer()
                Button("完成") { dismiss() }
            }

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundColor(testResult.hasPrefix("✓") ? .green : .red)
            }

            Spacer()
        }
        .textFieldStyle(.roundedBorder)
        .padding(16)
    }

    private func save() {
        let id = selectedID ?? UUID().uuidString.lowercased()
        let provider = AiProviderConfig(id: id, name: name, baseUrl: baseURL, model: model, maxTokens: nil)
        bridge.saveProvider(provider)
        try? bridge.vault.setKey(apiKey.isEmpty ? nil : apiKey, providerID: id)
        selectedID = id
        testResult = "✓ 已保存"
    }

    private func testConnectivity() {
        isTesting = true
        testResult = nil
        let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces))?
            .appendingPathComponent("chat/completions")
        guard let url else {
            testResult = "URL 无效"
            isTesting = false
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1,
        ])

        Task {
            defer { isTesting = false }
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                switch status {
                case 200..<300: testResult = "✓ 连接成功"
                case 401, 403: testResult = "鉴权失败(检查 API Key)"
                case 404: testResult = "接口不存在(检查 Base URL)"
                default: testResult = "HTTP \(status)"
                }
            } catch let error as URLError where error.code == .timedOut {
                testResult = "超时(检查网络或 Base URL)"
            } catch let error as URLError where error.code == .cannotFindHost {
                testResult = "域名无法解析"
            } catch {
                testResult = "失败:\(error.localizedDescription)"
            }
        }
    }
}
