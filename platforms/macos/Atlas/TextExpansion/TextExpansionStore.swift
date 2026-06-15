import Foundation

protocol TextExpansionStoring {
    func snippets() -> [TextSnippet]
    func save(_ snippets: [TextSnippet]) throws
    func upsert(_ snippet: TextSnippet) throws
    func delete(id: UUID) throws
}

enum TextExpansionStoreError: LocalizedError, Equatable {
    case invalidSnippet
    case duplicateTrigger

    var errorDescription: String? {
        switch self {
        case .invalidSnippet: return "Snippets require a trigger and an expansion."
        case .duplicateTrigger: return "Snippet triggers must be unique."
        }
    }
}

final class TextExpansionStore: TextExpansionStoring {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = TextExpansionStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func snippets() -> [TextSnippet] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([TextSnippet].self, from: data)) ?? []
    }

    func save(_ snippets: [TextSnippet]) throws {
        guard snippets.allSatisfy(\.isValid) else { throw TextExpansionStoreError.invalidSnippet }
        let triggers = snippets.map { $0.trigger.lowercased() }
        guard Set(triggers).count == triggers.count else { throw TextExpansionStoreError.duplicateTrigger }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(snippets).write(to: fileURL, options: [.atomic])
    }

    func upsert(_ snippet: TextSnippet) throws {
        guard snippet.isValid else { throw TextExpansionStoreError.invalidSnippet }
        var current = snippets()
        if let index = current.firstIndex(where: { $0.id == snippet.id }) {
            current[index] = snippet
        } else {
            current.append(snippet)
        }
        try save(current.sorted { $0.trigger.localizedCaseInsensitiveCompare($1.trigger) == .orderedAscending })
    }

    func delete(id: UUID) throws {
        try save(snippets().filter { $0.id != id })
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("text-expansion.json")
    }
}

final class InMemoryTextExpansionStore: TextExpansionStoring {
    private var store: [TextSnippet]
    init(snippets: [TextSnippet] = []) { store = snippets }
    func snippets() -> [TextSnippet] { store }
    func save(_ snippets: [TextSnippet]) throws { store = snippets }
    func upsert(_ snippet: TextSnippet) throws {
        if let i = store.firstIndex(where: { $0.id == snippet.id }) { store[i] = snippet } else { store.append(snippet) }
    }
    func delete(id: UUID) throws { store.removeAll { $0.id == id } }
}
