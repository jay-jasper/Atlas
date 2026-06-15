import Foundation

protocol RCFileAccessing {
    func read() -> String
    func write(_ content: String) throws
}

struct ZshrcFileAccess: RCFileAccessing {
    private var path: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc").path
    }
    func read() -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
    func write(_ content: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

@MainActor
final class EnvService: ObservableObject {
    @Published private(set) var variables: [EnvVariable] = []
    @Published private(set) var statusMessage: String = ""

    private let access: RCFileAccessing

    init(access: RCFileAccessing = ZshrcFileAccess()) {
        self.access = access
        reload()
    }

    func reload() {
        variables = EnvDocument.parseManaged(access.read())
    }

    func set(key: String, value: String) {
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { return }
        var updated = variables.filter { $0.key != trimmedKey }
        updated.append(EnvVariable(key: trimmedKey, value: value))
        updated.sort { $0.key < $1.key }
        persist(updated)
    }

    func remove(key: String) {
        persist(variables.filter { $0.key != key })
    }

    private func persist(_ updated: [EnvVariable]) {
        do {
            try access.write(EnvDocument.applyManaged(updated, to: access.read()))
            statusMessage = "Saved to ~/.zshrc — open a new shell to apply."
            variables = updated
        } catch {
            statusMessage = "Could not write ~/.zshrc."
        }
    }
}
