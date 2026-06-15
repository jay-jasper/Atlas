import AppKit
import Foundation

@MainActor
final class ScriptingService: ObservableObject {
    @Published var script: String = "-- Atlas script\nclipboard.set Hello from Lua"
    @Published private(set) var output: String = ""
    @Published private(set) var availableCommands: [String] = []

    let api = AtlasScriptAPI()
    private let runner: ScriptRunning

    init(runner: ScriptRunning = LineScriptRunner()) {
        self.runner = runner
        registerBuiltins()
        availableCommands = api.available()
    }

    func run() {
        switch runner.run(script, api: api) {
        case .ok(let message): output = message.isEmpty ? "✓ done" : message
        case .error(let message): output = "✗ \(message)"
        }
    }

    /// Exposes a curated set of Atlas actions to scripts.
    private func registerBuiltins() {
        api.register("clipboard.set") { args in
            let text = args.joined(separator: " ")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return .ok("clipboard set")
        }
        api.register("clipboard.get") { _ in
            .ok(NSPasteboard.general.string(forType: .string) ?? "")
        }
        api.register("notify") { args in
            .ok("notified: \(args.joined(separator: " "))")
        }
        api.register("open.url") { args in
            guard let first = args.first, let url = URL(string: first) else {
                return .error("open.url requires a URL")
            }
            NSWorkspace.shared.open(url)
            return .ok("opened \(first)")
        }
    }
}
