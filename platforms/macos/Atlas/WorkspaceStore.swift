import Foundation

protocol WorkspaceStoring {
    func load() throws -> [Workspace]
    func save(_ workspace: Workspace) throws
    func delete(id: UUID) throws
}

final class WorkspaceStore: WorkspaceStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = WorkspaceStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [Workspace] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.workspaceDecoder
            .decode([Workspace].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ workspace: Workspace) throws {
        var workspaces = try load().filter { $0.id != workspace.id }
        workspaces.append(workspace)
        try write(workspaces.sorted { $0.updatedAt > $1.updatedAt })
    }

    func delete(id: UUID) throws {
        try write(try load().filter { $0.id != id })
    }

    private func write(_ workspaces: [Workspace]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.workspaceEncoder.encode(workspaces)
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("workspaces.json")
    }
}
