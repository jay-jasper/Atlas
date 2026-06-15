import Foundation

/// The result of invoking an Atlas script command.
enum ScriptResult: Equatable {
    case ok(String)
    case error(String)
}

/// The Atlas API surface exposed to user scripts (e.g. via an embedded Lua VM).
/// Commands are addressed as `module.action` and invoked with string arguments.
/// The registry + dispatch is pure and unit-testable; the Lua runtime calls into
/// this same surface.
final class AtlasScriptAPI {
    private var commands: [String: ([String]) -> ScriptResult] = [:]

    /// Registers a callable command, e.g. `register("screenshot.capture") { ... }`.
    func register(_ name: String, handler: @escaping ([String]) -> ScriptResult) {
        commands[name.lowercased()] = handler
    }

    /// Whether a command is available.
    func has(_ name: String) -> Bool {
        commands[name.lowercased()] != nil
    }

    /// All registered command names, sorted.
    func available() -> [String] {
        commands.keys.sorted()
    }

    /// Invokes a command by name with arguments.
    func dispatch(_ name: String, args: [String] = []) -> ScriptResult {
        guard let handler = commands[name.lowercased()] else {
            return .error("unknown command '\(name)'")
        }
        return handler(args)
    }
}

/// Runs a user script against the Atlas API. The live implementation embeds a
/// Lua VM; injected so the bridge is testable.
protocol ScriptRunning {
    func run(_ script: String, api: AtlasScriptAPI) -> ScriptResult
}

/// A minimal built-in runner that interprets one `module.action arg1 arg2` call
/// per line — a dependency-free fallback before the Lua VM is embedded. It is
/// also a complete, testable command dispatcher in its own right.
struct LineScriptRunner: ScriptRunning {
    func run(_ script: String, api: AtlasScriptAPI) -> ScriptResult {
        var lastResult: ScriptResult = .ok("")
        for rawLine in script.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("--") { continue } // blank / Lua comment
            let tokens = line.split(separator: " ").map(String.init)
            guard let name = tokens.first else { continue }
            lastResult = api.dispatch(name, args: Array(tokens.dropFirst()))
            if case .error = lastResult { return lastResult }
        }
        return lastResult
    }
}
