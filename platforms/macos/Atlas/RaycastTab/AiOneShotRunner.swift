import Foundation

/// 一次性 AI 调用(翻译/AI 指令共用):临时 session 发送 prompt,
/// 流式回调聚合,完成后清掉临时 session。引擎沿用 AI tab 的选择(CLI/BYOK)。
@MainActor
final class AiOneShotRunner: ObservableObject {
    @Published private(set) var output: String = ""
    @Published private(set) var isStreaming = false
    @Published var lastError: String?

    private let engineStore = AIEngineStore()
    private let vault = AIKeyVault()
    private var requestID: UInt64?
    private var delegate: OneShotDelegate?
    private var sessionID: String?
    private var completion: ((String) -> Void)?

    var isConfigured: Bool {
        if engineStore.engine != nil { return true }
        return !((try? aiListProviders()) ?? []).isEmpty
    }

    func run(prompt: String, onDone: ((String) -> Void)? = nil) {
        guard !isStreaming else { return }
        output = ""
        lastError = nil
        completion = onDone

        let session = AiChatSession(
            id: "oneshot-" + UUID().uuidString.lowercased(),
            title: "oneshot",
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            presetId: nil,
            providerId: nil,
            messages: [AiChatMessage(
                id: UUID().uuidString.lowercased(),
                role: "user",
                text: prompt,
                imagePaths: [],
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                error: nil
            )]
        )
        do {
            try aiSaveSession(session: session)
        } catch {
            lastError = error.localizedDescription
            return
        }
        sessionID = session.id
        let delegate = OneShotDelegate(runner: self)
        self.delegate = delegate
        isStreaming = true

        do {
            switch engineStore.engine {
            case .cli(let cliID, let cliPath, let model):
                requestID = try aiSendViaCli(
                    sessionId: session.id, cliId: cliID, cliPath: cliPath,
                    model: model, delegate: delegate
                )
            case .byok(let providerID):
                try sendByok(sessionID: session.id, providerID: providerID, delegate: delegate)
            case nil:
                let providers = (try? aiListProviders()) ?? []
                guard let first = providers.first else {
                    isStreaming = false
                    lastError = loc("先在 AI tab 配置引擎", "Configure an AI engine in the AI tab first")
                    cleanup()
                    return
                }
                try sendByok(sessionID: session.id, providerID: first.id, delegate: delegate)
            }
        } catch {
            isStreaming = false
            lastError = error.localizedDescription
            cleanup()
        }
    }

    private func sendByok(sessionID: String, providerID: String, delegate: OneShotDelegate) throws {
        let providers = (try? aiListProviders()) ?? []
        guard let provider = providers.first(where: { $0.id == providerID }) ?? providers.first else {
            throw NSError(domain: "atlas.oneshot", code: 1, userInfo: [
                NSLocalizedDescriptionKey: loc("Provider 未配置", "Provider not configured"),
            ])
        }
        guard let apiKey = vault.key(providerID: provider.id), !apiKey.isEmpty else {
            throw NSError(domain: "atlas.oneshot", code: 2, userInfo: [
                NSLocalizedDescriptionKey: loc("Provider 缺少 API Key", "Provider has no API key"),
            ])
        }
        requestID = try aiSendMessage(
            sessionId: sessionID, provider: provider, apiKey: apiKey,
            systemPrompt: nil, delegate: delegate
        )
    }

    func cancel() {
        if let id = requestID { aiCancel(requestId: id) }
        isStreaming = false
        cleanup()
    }

    fileprivate func handleDelta(_ text: String) {
        output += text
    }

    fileprivate func handleDone() {
        isStreaming = false
        completion?(output)
        completion = nil
        cleanup()
    }

    fileprivate func handleError(_ message: String) {
        isStreaming = false
        lastError = message
        completion = nil
        cleanup()
    }

    private func cleanup() {
        if let id = sessionID {
            try? aiDeleteSession(id: id)
            sessionID = nil
        }
    }
}

private final class OneShotDelegate: AiChatStreamDelegate, @unchecked Sendable {
    weak var runner: AiOneShotRunner?

    init(runner: AiOneShotRunner) {
        self.runner = runner
    }

    func onDelta(requestId: UInt64, text: String) {
        Task { @MainActor [weak runner] in runner?.handleDelta(text) }
    }

    func onDone(requestId: UInt64) {
        Task { @MainActor [weak runner] in runner?.handleDone() }
    }

    func onError(requestId: UInt64, message: String) {
        Task { @MainActor [weak runner] in runner?.handleError(message) }
    }
}
