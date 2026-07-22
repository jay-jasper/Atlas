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

/// CLI 扫描结果缓存:面板秒开,后台再静默刷新。
enum CliScanCache {
    private static let storageKey = "ai.cli.cache"

    private struct Entry: Codable {
        let kindId: String
        let display: String
        let subtitle: String
        let path: String
        let version: String
        let defaultModels: [String]
    }

    static func load(defaults: UserDefaults = .standard) -> [AiDetectedCli] {
        guard let data = defaults.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.map {
            AiDetectedCli(
                kindId: $0.kindId,
                display: $0.display,
                subtitle: $0.subtitle,
                path: $0.path,
                version: $0.version,
                defaultModels: $0.defaultModels
            )
        }
    }

    static func save(_ clis: [AiDetectedCli], defaults: UserDefaults = .standard) {
        let entries = clis.map {
            Entry(
                kindId: $0.kindId,
                display: $0.display,
                subtitle: $0.subtitle,
                path: $0.path,
                version: $0.version,
                defaultModels: $0.defaultModels
            )
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
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
