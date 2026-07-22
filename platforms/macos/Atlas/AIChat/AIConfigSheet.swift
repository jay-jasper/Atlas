import SwiftUI

/// BYOK 供应商预设(chips → 表单模板)。
struct ByokPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let baseURL: String
    let defaultModel: String
    let keyURL: String?

    static let all: [ByokPreset] = [
        ByokPreset(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", defaultModel: "gpt-4o", keyURL: "https://platform.openai.com/api-keys"),
        ByokPreset(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", defaultModel: "deepseek-chat", keyURL: "https://platform.deepseek.com/api_keys"),
        ByokPreset(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", defaultModel: "openrouter/auto", keyURL: "https://openrouter.ai/keys"),
        ByokPreset(id: "qwen", name: "千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "qwen-plus", keyURL: "https://bailian.console.aliyun.com/?apiKey=1"),
        ByokPreset(id: "volcengine", name: "火山引擎", baseURL: "https://ark.cn-beijing.volces.com/api/v3", defaultModel: "doubao-pro-32k", keyURL: "https://console.volcengine.com/ark"),
        ByokPreset(id: "qianfan", name: "百度千帆", baseURL: "https://qianfan.baidubce.com/v2", defaultModel: "ernie-4.0-8k", keyURL: "https://console.bce.baidu.com/iam/#/iam/apikey/list"),
        ByokPreset(id: "vllm", name: "vLLM", baseURL: "http://localhost:8000/v1", defaultModel: "", keyURL: nil),
        ByokPreset(id: "minimax", name: "MiniMax", baseURL: "https://api.minimax.chat/v1", defaultModel: "abab6.5s-chat", keyURL: "https://platform.minimaxi.com/user-center/basic-information/interface-key"),
        ByokPreset(id: "moonshot", name: "Moonshot", baseURL: "https://api.moonshot.cn/v1", defaultModel: "moonshot-v1-8k", keyURL: "https://platform.moonshot.cn/console/api-keys"),
        ByokPreset(id: "zhipu", name: "智谱", baseURL: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-4-air", keyURL: "https://open.bigmodel.cn/usercenter/apikeys"),
        ByokPreset(id: "huggingface", name: "Hugging Face", baseURL: "https://router.huggingface.co/v1", defaultModel: "", keyURL: "https://huggingface.co/settings/tokens"),
        ByokPreset(id: "custom", name: "自定义提供方", baseURL: "", defaultModel: "", keyURL: nil),
    ]
}

/// AI 配置:本机 CLI | BYOK 双引擎(截图样式)。
struct AIConfigSheet: View {
    @ObservedObject var bridge: AIChatBridge
    @ObservedObject var engineStore: AIEngineStore
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case cli = "本机 CLI"
        case byok = "BYOK"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .cli

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI 引擎")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !embedded {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("在本机 CLI 与 BYOK 之间选择。")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .cli:
                CliEnginePage(bridge: bridge, engineStore: engineStore)
            case .byok:
                ByokEnginePage(bridge: bridge, engineStore: engineStore)
            }
        }
        .padding(16)
        .frame(width: embedded ? nil : 640, height: embedded ? nil : 560)
        .frame(maxWidth: embedded ? 760 : nil, maxHeight: embedded ? .infinity : nil, alignment: .topLeading)
        .onAppear {
            if case .byok = engineStore.engine { mode = .byok }
        }
    }
}

// MARK: - 本机 CLI

private struct CliEnginePage: View {
    @ObservedObject var bridge: AIChatBridge
    @ObservedObject var engineStore: AIEngineStore

    @State private var clis: [AiDetectedCli] = CliScanCache.load()
    @State private var selectedModel: [String: String] = [:]
    @State private var testResult: [String: String] = [:]
    @State private var isScanning = false

    private var selectedCliID: String? {
        if case .cli(let id, _, _) = engineStore.engine { return id }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择用来运行提示词的 CLI。")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("你的 CLI(\(clis.count))")
                    .font(.callout.weight(.semibold))
                if isScanning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button {
                    scan(manual: true)
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                        .font(.callout)
                }
                .disabled(isScanning)
            }

            if clis.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text(isScanning ? "扫描中…" : "尚未扫描。点「重新扫描」检测已安装的 agent CLI(Claude Code / Codex 等)。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(clis, id: \.kindId) { cli in
                            cliCard(cli)
                        }
                    }
                }
            }
        }
        .onAppear {
            // 默认不扫描:有缓存列表时才后台静默刷新;首次由用户点「重新扫描」。
            if !clis.isEmpty {
                scan(manual: false)
            }
        }
    }

    private func cliCard(_ cli: AiDetectedCli) -> some View {
        let isSelected = selectedCliID == cli.kindId
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconTile(systemImage: "terminal", tint: isSelected ? .accentColor : .gray)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(cli.display)
                            .font(.system(size: 13, weight: .semibold))
                        Text("·  \(cli.subtitle)")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                Button("测试") { test(cli) }
                    .font(.callout)
            }

            if isSelected {
                VStack(alignment: .leading, spacing: 4) {
                    Text("模型 · 内置列表")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if cli.defaultModels.isEmpty {
                        Text("Default (CLI config)")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("", selection: Binding(
                            get: { selectedModel[cli.kindId] ?? cli.defaultModels.first ?? "" },
                            set: { model in
                                selectedModel[cli.kindId] = model
                                engineStore.engine = .cli(id: cli.kindId, path: cli.path, model: model)
                            }
                        )) {
                            ForEach(cli.defaultModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                }
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
            let model = selectedModel[cli.kindId] ?? cli.defaultModels.first
            engineStore.engine = .cli(id: cli.kindId, path: cli.path, model: model)
        }
    }

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

// MARK: - BYOK

private struct ByokEnginePage: View {
    @ObservedObject var bridge: AIChatBridge
    @ObservedObject var engineStore: AIEngineStore

    @State private var presetID: String = "openai"
    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @State private var baseURL = ByokPreset.all[0].baseURL
    @State private var maxTokensText = ""
    @State private var model = ByokPreset.all[0].defaultModel
    @State private var statusText: String?

    private var preset: ByokPreset {
        ByokPreset.all.first { $0.id == presetID } ?? ByokPreset.all[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 供应商预设 chips
                FlowChips(presets: ByokPreset.all, selectedID: presetID) { chosen in
                    presetID = chosen.id
                    baseURL = chosen.baseURL
                    model = chosen.defaultModel
                    statusText = nil
                    loadExistingProvider()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("\(preset.name) API")
                        .font(.callout.weight(.semibold))

                    HStack {
                        Text("API Key")
                            .font(.caption.weight(.medium))
                        Text("*").foregroundColor(.red)
                        Spacer()
                        if let keyURL = preset.keyURL, let url = URL(string: keyURL) {
                            Link("获取 key ↗", destination: url)
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
                        Button(isKeyVisible ? "隐藏" : "显示") { isKeyVisible.toggle() }
                            .font(.caption)
                    }
                    Text("仅保存在本机(Keychain 密封)。")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    field("Base URL", required: true) {
                        TextField("https://…", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("最大 tokens(可选)", required: false) {
                        TextField("留空使用模型默认", text: $maxTokensText)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("模型", required: true) {
                        TextField("模型 ID", text: $model)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Button("保存并使用") { save() }
                            .buttonStyle(.borderedProminent)
                            .disabled(baseURL.isEmpty || model.isEmpty)
                        if let statusText {
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(statusText.hasPrefix("✓") ? .green : .red)
                        }
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .onAppear { loadExistingProvider() }
    }

    private func field(_ label: String, required: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text(label).font(.caption.weight(.medium))
                if required { Text("*").foregroundColor(.red) }
            }
            content()
        }
    }

    private func loadExistingProvider() {
        if let existing = bridge.providers.first(where: { $0.id == "byok-\(presetID)" }) {
            baseURL = existing.baseUrl
            model = existing.model
            maxTokensText = existing.maxTokens.map(String.init) ?? ""
            apiKey = bridge.vault.key(providerID: existing.id) ?? ""
        }
    }

    private func save() {
        let id = "byok-\(presetID)"
        let provider = AiProviderConfig(
            id: id,
            name: preset.name,
            baseUrl: baseURL.trimmingCharacters(in: .whitespaces),
            model: model.trimmingCharacters(in: .whitespaces),
            maxTokens: UInt32(maxTokensText.trimmingCharacters(in: .whitespaces))
        )
        bridge.saveProvider(provider)
        try? bridge.vault.setKey(apiKey.isEmpty ? nil : apiKey, providerID: id)
        bridge.selectedProviderID = id
        engineStore.engine = .byok(providerID: id)
        statusText = "✓ 已保存并设为当前引擎"
    }
}

/// 简易流式 chips 布局(固定 4 列网格,预设数量固定可控)。
private struct FlowChips: View {
    let presets: [ByokPreset]
    let selectedID: String
    let onSelect: (ByokPreset) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(presets) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(selectedID == preset.id ? Color.accentColor : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(preset.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(
                            selectedID == preset.id
                                ? Color.accentColor.opacity(0.15)
                                : Color.primary.opacity(0.05)
                        )
                    )
                    .overlay(
                        Capsule().stroke(
                            selectedID == preset.id ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }
}
