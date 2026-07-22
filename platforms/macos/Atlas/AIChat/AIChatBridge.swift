import Foundation

/// Main-actor wrapper over the atlas-ai FFI surface. Owns published UI state;
/// stream callbacks hop from the Rust background thread to the main actor.
@MainActor
final class AIChatBridge: ObservableObject {
    @Published private(set) var providers: [AiProviderConfig] = []
    @Published private(set) var sessions: [AiSessionSummary] = []
    @Published private(set) var presets: [AiPromptPreset] = []
    @Published var activeSession: AiChatSession?
    @Published private(set) var streamingText: String = ""
    @Published private(set) var isStreaming: Bool = false
    @Published var lastError: String?

    @Published var selectedProviderID: String?
    @Published var selectedPresetID: String?

    let vault: AIKeyVault
    let engineStore = AIEngineStore()
    private var currentRequestID: UInt64?
    private var streamDelegate: StreamDelegate?

    init(
        vault: AIKeyVault = AIKeyVault(),
        storageDir: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas/ai", isDirectory: true)
    ) {
        self.vault = vault
        aiSetStorageDir(path: storageDir.path)
        refresh()
    }

    // MARK: Loading

    func refresh() {
        providers = (try? aiListProviders()) ?? []
        sessions = (try? aiListSessions()) ?? []
        presets = (try? aiListPresets()) ?? []
        if selectedProviderID == nil { selectedProviderID = providers.first?.id }
    }

    // MARK: Sessions

    func newSession() {
        let session = AiChatSession(
            id: UUID().uuidString.lowercased(),
            title: "新对话",
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            presetId: selectedPresetID,
            providerId: selectedProviderID,
            messages: []
        )
        try? aiSaveSession(session: session)
        activeSession = session
        refresh()
    }

    func open(_ id: String) {
        do {
            activeSession = try aiLoadSession(id: id)
            selectedProviderID = activeSession?.providerId ?? selectedProviderID
            selectedPresetID = activeSession?.presetId
        } catch {
            lastError = "会话打开失败:\(error.localizedDescription)"
        }
    }

    func deleteSession(_ id: String) {
        try? aiDeleteSession(id: id)
        if activeSession?.id == id { activeSession = nil }
        refresh()
    }

    func rename(_ id: String, title: String) {
        guard var session = try? aiLoadSession(id: id) else { return }
        session.title = title
        try? aiSaveSession(session: session)
        if activeSession?.id == id { activeSession = session }
        refresh()
    }

    func exportMarkdown() -> String? {
        guard let id = activeSession?.id else { return nil }
        return try? aiExportSessionMarkdown(id: id)
    }

    // MARK: Presets / providers

    func saveProvider(_ provider: AiProviderConfig) {
        try? aiSaveProvider(provider: provider)
        refresh()
    }

    func deleteProvider(_ id: String) {
        try? aiDeleteProvider(id: id)
        try? vault.setKey(nil, providerID: id)
        refresh()
    }

    func savePreset(_ preset: AiPromptPreset) {
        try? aiSavePreset(preset: preset)
        refresh()
    }

    func deletePreset(_ id: String) {
        try? aiDeletePreset(id: id)
        if selectedPresetID == id { selectedPresetID = nil }
        refresh()
    }

    // MARK: Sending

    func send(text: String, imagePaths: [String]) {
        guard !isStreaming else { return }
        guard var session = activeSession else { return }

        let message = AiChatMessage(
            id: UUID().uuidString.lowercased(),
            role: "user",
            text: text,
            imagePaths: imagePaths,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            error: nil
        )
        session.messages.append(message)
        session.presetId = selectedPresetID
        if session.messages.count == 1 {
            session.title = Self.title(for: text)
        }

        let systemPrompt = presets.first(where: { $0.id == selectedPresetID })?.systemPrompt
        let delegate = StreamDelegate(bridge: self)

        switch engineStore.engine {
        case .cli(let cliID, let cliPath, let model):
            try? aiSaveSession(session: session)
            activeSession = session
            refresh()
            lastError = nil
            streamingText = ""
            isStreaming = true
            streamDelegate = delegate
            do {
                currentRequestID = try aiSendViaCli(
                    sessionId: session.id,
                    cliId: cliID,
                    cliPath: cliPath,
                    model: model,
                    delegate: delegate
                )
            } catch {
                isStreaming = false
                lastError = "发送失败:\(error.localizedDescription)"
            }

        case .byok(let providerID):
            sendViaByok(session: session, providerID: providerID, systemPrompt: systemPrompt, delegate: delegate)

        case nil:
            // 未显式选择引擎:有 provider 则走 BYOK 兼容旧行为,否则提示配置。
            if let fallback = selectedProviderID ?? providers.first?.id {
                sendViaByok(session: session, providerID: fallback, systemPrompt: systemPrompt, delegate: delegate)
            } else {
                lastError = "先在 AI 配置里选择本机 CLI 或配置 BYOK"
            }
        }
    }

    private func sendViaByok(
        session: AiChatSession,
        providerID: String,
        systemPrompt: String?,
        delegate: StreamDelegate
    ) {
        var session = session
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            lastError = "Provider 不存在,请重新配置"
            return
        }
        guard let apiKey = vault.key(providerID: provider.id), !apiKey.isEmpty else {
            lastError = "Provider「\(provider.name)」还没有配置 API Key"
            return
        }
        session.providerId = provider.id
        try? aiSaveSession(session: session)
        activeSession = session
        refresh()
        lastError = nil
        streamingText = ""
        isStreaming = true
        streamDelegate = delegate
        do {
            currentRequestID = try aiSendMessage(
                sessionId: session.id,
                provider: provider,
                apiKey: apiKey,
                systemPrompt: systemPrompt,
                delegate: delegate
            )
        } catch {
            isStreaming = false
            lastError = "发送失败:\(error.localizedDescription)"
        }
    }

    func cancel() {
        if let id = currentRequestID {
            aiCancel(requestId: id)
        }
    }

    func retryLast() {
        guard var session = activeSession,
              let lastUser = session.messages.last(where: { $0.role == "user" }) else { return }
        // Drop trailing failed assistant turn if present, then resend.
        if let last = session.messages.last, last.role == "assistant", last.error != nil {
            session.messages.removeLast()
            try? aiSaveSession(session: session)
            activeSession = session
        }
        send(text: lastUser.text, imagePaths: lastUser.imagePaths)
    }

    // MARK: Stream handling (internal, main actor)

    func apply(delta: String) {
        streamingText += delta
    }

    func finishStream(error: String?) {
        guard var session = activeSession else {
            isStreaming = false
            streamingText = ""
            return
        }
        if !streamingText.isEmpty || error != nil {
            let assistant = AiChatMessage(
                id: UUID().uuidString.lowercased(),
                role: "assistant",
                text: streamingText,
                imagePaths: [],
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                error: error
            )
            session.messages.append(assistant)
            try? aiSaveSession(session: session)
            activeSession = session
        }
        if let error {
            lastError = error
        }
        streamingText = ""
        isStreaming = false
        currentRequestID = nil
        streamDelegate = nil
        refresh()
    }

    static func title(for text: String) -> String {
        let firstLine = text
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "新对话"
        return firstLine.count > 24 ? String(firstLine.prefix(24)) + "…" : firstLine
    }
}

/// Hops Rust background-thread callbacks onto the main actor.
private final class StreamDelegate: AiChatStreamDelegate, @unchecked Sendable {
    private weak var bridge: AIChatBridge?

    init(bridge: AIChatBridge) {
        self.bridge = bridge
    }

    func onDelta(requestId: UInt64, text: String) {
        Task { @MainActor [weak bridge] in bridge?.apply(delta: text) }
    }

    func onDone(requestId: UInt64) {
        Task { @MainActor [weak bridge] in bridge?.finishStream(error: nil) }
    }

    func onError(requestId: UInt64, message: String) {
        Task { @MainActor [weak bridge] in bridge?.finishStream(error: message) }
    }
}
