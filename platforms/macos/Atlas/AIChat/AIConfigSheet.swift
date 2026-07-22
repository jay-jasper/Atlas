import AppKit
import SwiftUI

/// 品牌图标(CodexBar MIT 资源);缺图标的供应商回退首字母色块。
struct ProviderIconView: View {
    let iconName: String?     // "claude" → ProviderIcon-claude.svg
    let fallbackText: String
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let iconName,
               let url = Bundle.main.url(forResource: "ProviderIcon-\(iconName)", withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Text(String(fallbackText.prefix(2)))
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
    }
}

/// 云端 API 供应商预设(含品牌图标)。
struct ByokPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String?
    let baseURL: String
    let defaultModel: String
    let keyURL: String?
    var requiresKey: Bool = true

    static let all: [ByokPreset] = [
        ByokPreset(id: "openai", name: "OpenAI", icon: nil, baseURL: "https://api.openai.com/v1", defaultModel: "gpt-4o", keyURL: "https://platform.openai.com/api-keys"),
        ByokPreset(id: "deepseek", name: "DeepSeek", icon: "deepseek", baseURL: "https://api.deepseek.com/v1", defaultModel: "deepseek-chat", keyURL: "https://platform.deepseek.com/api_keys"),
        ByokPreset(id: "openrouter", name: "OpenRouter", icon: "openrouter", baseURL: "https://openrouter.ai/api/v1", defaultModel: "openrouter/auto", keyURL: "https://openrouter.ai/keys"),
        ByokPreset(id: "grok", name: "Grok (xAI)", icon: "grok", baseURL: "https://api.x.ai/v1", defaultModel: "grok-3", keyURL: "https://console.x.ai"),
        ByokPreset(id: "mistral", name: "Mistral", icon: "mistral", baseURL: "https://api.mistral.ai/v1", defaultModel: "mistral-large-latest", keyURL: "https://console.mistral.ai/api-keys"),
        ByokPreset(id: "groq", name: "Groq", icon: "groq", baseURL: "https://api.groq.com/openai/v1", defaultModel: "llama-3.3-70b-versatile", keyURL: "https://console.groq.com/keys"),
        ByokPreset(id: "qwen", name: "千问", icon: "alibaba", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "qwen-plus", keyURL: "https://bailian.console.aliyun.com/?apiKey=1"),
        ByokPreset(id: "volcengine", name: "火山引擎", icon: "doubao", baseURL: "https://ark.cn-beijing.volces.com/api/v3", defaultModel: "doubao-pro-32k", keyURL: "https://console.volcengine.com/ark"),
        ByokPreset(id: "moonshot", name: "Moonshot", icon: "kimi", baseURL: "https://api.moonshot.cn/v1", defaultModel: "moonshot-v1-8k", keyURL: "https://platform.moonshot.cn/console/api-keys"),
        ByokPreset(id: "zhipu", name: "智谱", icon: "zai", baseURL: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-4-air", keyURL: "https://open.bigmodel.cn/usercenter/apikeys"),
        ByokPreset(id: "minimax", name: "MiniMax", icon: "minimax", baseURL: "https://api.minimax.chat/v1", defaultModel: "abab6.5s-chat", keyURL: "https://platform.minimaxi.com/user-center/basic-information/interface-key"),
        ByokPreset(id: "qianfan", name: "百度千帆", icon: nil, baseURL: "https://qianfan.baidubce.com/v2", defaultModel: "ernie-4.0-8k", keyURL: "https://console.bce.baidu.com/iam/#/iam/apikey/list"),
        ByokPreset(id: "huggingface", name: "Hugging Face", icon: nil, baseURL: "https://router.huggingface.co/v1", defaultModel: "", keyURL: "https://huggingface.co/settings/tokens"),
        ByokPreset(id: "ollama", name: "Ollama", icon: "ollama", baseURL: "http://localhost:11434/v1", defaultModel: "llama3.2", keyURL: nil, requiresKey: false),
        ByokPreset(id: "vllm", name: "vLLM", icon: nil, baseURL: "http://localhost:8000/v1", defaultModel: "", keyURL: nil, requiresKey: false),
        ByokPreset(id: "custom", name: "自定义提供方", icon: nil, baseURL: "", defaultModel: "", keyURL: nil),
    ]
}

/// 本机 CLI 的品牌图标映射。
private let cliIconNames: [String: String] = [
    "claude-code": "claude",
    "codex": "codex",
    "gemini": "gemini",
    "opencode": "opencode",
]

/// AI 引擎配置:本机 CLI 与云端 API 合并为一张供应商列表。
struct AIConfigSheet: View {
    @ObservedObject var bridge: AIChatBridge
    @ObservedObject var engineStore: AIEngineStore
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var clis: [AiDetectedCli] = CliScanCache.load()
    @State private var selectedModel: [String: String] = [:]
    @State private var testResult: [String: String] = [:]
    @State private var isScanning = false
    @State private var expandedPresetID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc("AI 引擎", "AI Engine"))
                    .font(.title3.weight(.semibold))
                Spacer()
                if !embedded {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }
            }
            Text(loc("选择本机 CLI 或云端 API 供应商作为对话引擎。", "Pick a local CLI or a cloud API provider."))
                .font(.caption)
                .foregroundColor(.secondary)

            cliSection
            byokSection
        }
        .padding(16)
        .frame(width: embedded ? nil : 640, height: embedded ? nil : 560)
        .frame(maxWidth: embedded ? 760 : nil, alignment: .topLeading)
        .onAppear {
            if !clis.isEmpty { scan(manual: false) }
        }
    }

    // MARK: 本机 CLI

    private var cliSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loc("本机 CLI(\(clis.count))", "Local CLIs (\(clis.count))"))
                    .font(.callout.weight(.semibold))
                if isScanning { ProgressView().controlSize(.small) }
                Spacer()
                Button {
                    scan(manual: true)
                } label: {
                    Label(loc("重新扫描", "Rescan"), systemImage: "arrow.clockwise")
                        .font(.callout)
                }
                .disabled(isScanning)
            }

            if clis.isEmpty {
                Text(isScanning
                     ? loc("扫描中…", "Scanning…")
                     : loc("尚未扫描。点「重新扫描」检测已安装的 agent CLI。", "Not scanned yet — hit Rescan."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                ForEach(clis, id: \.kindId) { cli in
                    cliRow(cli)
                }
            }
        }
    }

    private var selectedCliID: String? {
        if case .cli(let id, _, _) = engineStore.engine { return id }
        return nil
    }

    private var selectedByokID: String? {
        if case .byok(let providerID) = engineStore.engine {
            return providerID.replacingOccurrences(of: "byok-", with: "")
        }
        return nil
    }

    private func cliRow(_ cli: AiDetectedCli) -> some View {
        let isSelected = selectedCliID == cli.kindId
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProviderIconView(iconName: cliIconNames[cli.kindId], fallbackText: cli.display)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(cli.display).font(.system(size: 13, weight: .semibold))
                        Text("· \(cli.subtitle)").font(.caption).foregroundColor(.secondary)
                    }
                    Text(cli.version.isEmpty ? cli.path : cli.version)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let result = testResult[cli.kindId] {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.hasPrefix("✓") ? .green : .red)
                }
                Button(loc("测试", "Test")) { test(cli) }
                    .font(.callout)
            }

            if isSelected, !cli.defaultModels.isEmpty {
                Picker(loc("模型", "Model"), selection: Binding(
                    get: { selectedModel[cli.kindId] ?? cli.defaultModels.first ?? "" },
                    set: { model in
                        selectedModel[cli.kindId] = model
                        engineStore.engine = .cli(id: cli.kindId, path: cli.path, model: model)
                    }
                )) {
                    ForEach(cli.defaultModels, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 280)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .focusable(false)
        .onTapGesture {
            engineStore.engine = .cli(
                id: cli.kindId,
                path: cli.path,
                model: selectedModel[cli.kindId] ?? cli.defaultModels.first
            )
        }
    }

    // MARK: 云端 API

    private var byokSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("云端 API(\(ByokPreset.all.count))", "Cloud APIs (\(ByokPreset.all.count))"))
                .font(.callout.weight(.semibold))
                .padding(.top, 4)

            ForEach(ByokPreset.all) { preset in
                ByokPresetRow(
                    preset: preset,
                    bridge: bridge,
                    engineStore: engineStore,
                    isSelected: selectedByokID == preset.id,
                    isExpanded: expandedPresetID == preset.id,
                    onToggleExpand: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            expandedPresetID = expandedPresetID == preset.id ? nil : preset.id
                        }
                    }
                )
            }
        }
    }

    // MARK: 扫描/测试

    private func scan(manual: Bool) {
        if manual { isScanning = true }
        let dirs = Self.searchDirs()
        Task.detached(priority: .userInitiated) {
            let found = aiDetectClis(searchDirs: dirs)
            await MainActor.run {
                clis = found
                CliScanCache.save(found)
                isScanning = false
            }
        }
    }

    private func test(_ cli: AiDetectedCli) {
        testResult[cli.kindId] = "…"
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cli.path)
            process.arguments = ["--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let ok = process.terminationStatus == 0
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    testResult[cli.kindId] = ok ? "✓ 可用" : "失败:\(output.prefix(200))"
                }
            } catch {
                DispatchQueue.main.async {
                    testResult[cli.kindId] = "失败:\(error.localizedDescription)"
                }
            }
        }
    }

    static func searchDirs() -> [String] {
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let home = NSHomeDirectory()
        for extra in ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/bin", "\(home)/.bun/bin", "\(home)/.cargo/bin"] {
            if !dirs.contains(extra) { dirs.append(extra) }
        }
        return dirs
    }
}

// MARK: - 云端供应商行(点击展开表单)

private struct ByokPresetRow: View {
    let preset: ByokPreset
    @ObservedObject var bridge: AIChatBridge
    @ObservedObject var engineStore: AIEngineStore
    let isSelected: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @State private var baseURL = ""
    @State private var maxTokensText = ""
    @State private var model = ""
    @State private var statusText: String?

    private var providerID: String { "byok-\(preset.id)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProviderIconView(iconName: preset.icon, fallbackText: preset.name)
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name).font(.system(size: 13, weight: .semibold))
                    Text(configuredSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Text(loc("当前引擎", "Active"))
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            if isExpanded {
                form
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
        .focusable(false)
        .onAppear { loadExisting() }
        .onChange(of: isExpanded) { expanded in
            if expanded { loadExisting() }
        }
    }

    private var configuredSummary: String {
        if let existing = bridge.providers.first(where: { $0.id == providerID }) {
            return existing.model.isEmpty ? existing.baseUrl : existing.model
        }
        return preset.baseURL.isEmpty ? loc("未配置", "Not configured") : preset.baseURL
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            if preset.requiresKey {
                HStack {
                    Text("API Key").font(.caption.weight(.medium))
                    Text("*").foregroundColor(.red)
                    Spacer()
                    if let keyURL = preset.keyURL, let url = URL(string: keyURL) {
                        Link(loc("获取 key ↗", "Get key ↗"), destination: url)
                            .font(.caption)
                    }
                }
                HStack(spacing: 6) {
                    Group {
                        if isKeyVisible {
                            TextField("sk-…", text: $apiKey)
                        } else {
                            SecureField("sk-…", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button(isKeyVisible ? loc("隐藏", "Hide") : loc("显示", "Show")) { isKeyVisible.toggle() }
                        .font(.caption)
                }
                Text(loc("仅保存在本机(Keychain 密封)。", "Stored locally only (sealed via Keychain)."))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            labeled("Base URL", required: true) {
                TextField("https://…", text: $baseURL).textFieldStyle(.roundedBorder)
            }
            labeled(loc("最大 tokens(可选)", "Max tokens (optional)"), required: false) {
                TextField(loc("留空使用模型默认", "Leave empty for model default"), text: $maxTokensText)
                    .textFieldStyle(.roundedBorder)
            }
            labeled(loc("模型", "Model"), required: true) {
                TextField("model id", text: $model).textFieldStyle(.roundedBorder)
            }

            HStack {
                Button(loc("保存并使用", "Save & Use")) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(baseURL.isEmpty || model.isEmpty || (preset.requiresKey && apiKey.isEmpty))
                if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(statusText.hasPrefix("✓") ? .green : .red)
                }
                Spacer()
            }
        }
        .padding(.top, 2)
    }

    private func labeled(_ label: String, required: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text(label).font(.caption.weight(.medium))
                if required { Text("*").foregroundColor(.red) }
            }
            content()
        }
    }

    private func loadExisting() {
        if let existing = bridge.providers.first(where: { $0.id == providerID }) {
            baseURL = existing.baseUrl
            model = existing.model
            maxTokensText = existing.maxTokens.map(String.init) ?? ""
            apiKey = bridge.vault.key(providerID: providerID) ?? ""
        } else {
            if baseURL.isEmpty { baseURL = preset.baseURL }
            if model.isEmpty { model = preset.defaultModel }
        }
    }

    private func save() {
        let provider = AiProviderConfig(
            id: providerID,
            name: preset.name,
            baseUrl: baseURL.trimmingCharacters(in: .whitespaces),
            model: model.trimmingCharacters(in: .whitespaces),
            maxTokens: UInt32(maxTokensText.trimmingCharacters(in: .whitespaces))
        )
        bridge.saveProvider(provider)
        try? bridge.vault.setKey(apiKey.isEmpty ? nil : apiKey, providerID: providerID)
        bridge.selectedProviderID = providerID
        engineStore.engine = .byok(providerID: providerID)
        statusText = loc("✓ 已保存并设为当前引擎", "✓ Saved and set as active engine")
    }
}
