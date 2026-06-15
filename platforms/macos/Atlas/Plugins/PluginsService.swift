import Foundation

/// A descriptor for an installed plugin and the Block Kit UI it currently emits.
struct PluginDescriptor: Equatable, Identifiable {
    var id: String { "\(name)@\(version)" }
    let name: String
    let version: String
    let track: String // "wasm" | "mcp"
    let ui: BlockKitNode
}

@MainActor
final class PluginsService: ObservableObject {
    @Published private(set) var plugins: [PluginDescriptor] = []
    @Published private(set) var lastEvent: BlockKitEvent?

    /// Loads a plugin from a descriptor and its Block Kit JSON. Returns false if
    /// the UI JSON is invalid.
    @discardableResult
    func install(name: String, version: String, track: String, uiJSON: String) -> Bool {
        guard let node = BlockKitNode.parse(uiJSON) else { return false }
        plugins.removeAll { $0.name == name }
        plugins.append(PluginDescriptor(name: name, version: version, track: track, ui: node))
        plugins.sort { $0.id < $1.id }
        return true
    }

    func uninstall(id: String) {
        plugins.removeAll { $0.id == id }
    }

    /// Routes a UI event from a rendered plugin back to the host (which forwards
    /// to the WASM/MCP runtime). Recorded here for observability/testing.
    func handle(_ event: BlockKitEvent) {
        lastEvent = event
    }
}
