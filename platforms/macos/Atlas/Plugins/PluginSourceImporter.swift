import Foundation

protocol PluginSourceBuilding: Sendable {
    func inspect(_ source: URL) throws -> String
    func build(_ source: URL, output: URL) throws -> URL
}

#if !ATLAS_STORE
struct RustPluginSourceBuilder: PluginSourceBuilding {
    func inspect(_ source: URL) throws -> String {
        try pluginSourceInspect(sourcePath: source.path)
    }

    func build(_ source: URL, output: URL) throws -> URL {
        URL(fileURLWithPath: try pluginSourceBuild(sourcePath: source.path, outputPath: output.path))
    }
}
#endif

struct PluginSourceImporter {
    private let builder: PluginSourceBuilding

    init(builder: PluginSourceBuilding) {
        self.builder = builder
    }

    func inspect(_ source: URL) async throws -> String {
        try await Task.detached { try builder.inspect(source) }.value
    }

    func build(_ source: URL) async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-\(UUID().uuidString).atlasplugin")
        return try await Task.detached { try builder.build(source, output: output) }.value
    }
}
