import Foundation

struct ShellScript: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var body: String

    init(id: UUID = UUID(), name: String, body: String) {
        self.id = id
        self.name = name
        self.body = body
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

protocol ShellScriptStoring {
    func scripts() -> [ShellScript]
    func save(_ scripts: [ShellScript]) throws
    func upsert(_ script: ShellScript) throws
    func delete(id: UUID) throws
}

enum ShellScriptStoreError: LocalizedError, Equatable {
    case invalidScript
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .invalidScript: return "Scripts require a name and a non-empty body."
        case .duplicateName: return "Script names must be unique."
        }
    }
}

final class ShellScriptStore: ShellScriptStoring {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = ShellScriptStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func scripts() -> [ShellScript] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([ShellScript].self, from: data)) ?? []
    }

    func save(_ scripts: [ShellScript]) throws {
        guard scripts.allSatisfy(\.isValid) else { throw ShellScriptStoreError.invalidScript }
        let names = scripts.map { $0.name.lowercased() }
        guard Set(names).count == names.count else { throw ShellScriptStoreError.duplicateName }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(scripts).write(to: fileURL, options: [.atomic])
    }

    func upsert(_ script: ShellScript) throws {
        guard script.isValid else { throw ShellScriptStoreError.invalidScript }
        var current = scripts()
        if let index = current.firstIndex(where: { $0.id == script.id }) {
            current[index] = script
        } else {
            current.append(script)
        }
        try save(current.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    func delete(id: UUID) throws {
        try save(scripts().filter { $0.id != id })
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("shell-scripts.json")
    }
}
