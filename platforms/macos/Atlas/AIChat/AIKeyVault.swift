import Foundation

/// Stores AI provider API keys as SecureLocalData-sealed files, one per
/// provider. Keys never enter the Rust persistence layer — they are read here
/// and passed per request.
final class AIKeyVault {
    private let directory: URL
    private let sealer: SecureLocalData

    init(
        directory: URL = AIKeyVault.defaultDirectory,
        sealer: SecureLocalData = .shared
    ) {
        self.directory = directory
        self.sealer = sealer
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas/ai/keys", isDirectory: true)
    }

    func setKey(_ key: String?, providerID: String) throws {
        let url = fileURL(providerID: providerID)
        guard let key, !key.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let sealed = try sealer.seal(Data(key.utf8))
        try sealed.write(to: url, options: .atomic)
    }

    func key(providerID: String) -> String? {
        let url = fileURL(providerID: providerID)
        guard let stored = try? Data(contentsOf: url),
              let opened = try? sealer.open(stored) else { return nil }
        return String(data: opened, encoding: .utf8)
    }

    private func fileURL(providerID: String) -> URL {
        let safe = providerID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return directory.appendingPathComponent("\(safe).key")
    }
}
