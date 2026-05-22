import Foundation

struct TokenBarLedger {
    let fileURL: URL

    init(
        fileURL: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("tokenbar-ledger.json")
    ) {
        self.fileURL = fileURL
    }

    func load() throws -> [TokenBarUsageEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([TokenBarUsageEntry].self, from: Data(contentsOf: fileURL))
    }

    func append(_ entry: TokenBarUsageEntry) throws {
        var entries = try load()
        entries.append(entry)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }

    func summary() throws -> TokenBarSummary {
        try load().reduce(.empty) { partial, entry in
            TokenBarSummary(
                inputTokens: partial.inputTokens + entry.inputTokens,
                outputTokens: partial.outputTokens + entry.outputTokens,
                costMicrosUSD: partial.costMicrosUSD + entry.costMicrosUSD
            )
        }
    }
}
