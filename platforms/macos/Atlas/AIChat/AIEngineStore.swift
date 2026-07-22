import Foundation

/// 当前对话引擎:本机 CLI 或 BYOK Provider。
enum AiEngine: Codable, Equatable {
    case cli(id: String, path: String, model: String?)
    case byok(providerID: String)

    var label: String {
        switch self {
        case .cli(let id, _, let model):
            let name = ["claude-code": "Claude Code", "codex": "Codex CLI", "gemini": "Gemini CLI",
                        "opencode": "OpenCode", "aider": "Aider"][id] ?? id
            return model.map { "\(name) · \($0)" } ?? name
        case .byok:
            return "BYOK"
        }
    }
}

@MainActor
final class AIEngineStore: ObservableObject {
    private static let storageKey = "ai.engine"

    @Published var engine: AiEngine? {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AiEngine.self, from: data) {
            engine = decoded
        } else {
            engine = nil
        }
    }

    private func save() {
        if let engine, let data = try? JSONEncoder().encode(engine) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}
