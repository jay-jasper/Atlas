import Foundation

struct Snippet: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let body: String
    let keywords: [String]
}

protocol SnippetProviding {
    func snippets() -> [Snippet]
}

final class SnippetStore: SnippetProviding {
    private static let storageKey = "snippets.items"

    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snippets() -> [Snippet] {
        guard
            let data = defaults.data(forKey: Self.storageKey),
            let snippets = try? decoder.decode([Snippet].self, from: data)
        else {
            return Self.defaultSnippets
        }
        return snippets
    }

    func save(_ snippets: [Snippet]) {
        let cleanSnippets = snippets.filter { snippet in
            !snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !snippet.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let data = try? encoder.encode(cleanSnippets) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    static let defaultSnippets: [Snippet] = [
        Snippet(
            id: "email-greeting",
            title: "Email Greeting",
            body: "Hi,\n\nThanks for reaching out.",
            keywords: ["email", "greeting", "hello"]
        ),
        Snippet(
            id: "meeting-notes",
            title: "Meeting Notes",
            body: "Notes:\n- \n\nNext steps:\n- ",
            keywords: ["meeting", "notes", "agenda"]
        ),
        Snippet(
            id: "bug-report",
            title: "Bug Report",
            body: "Summary:\n\nSteps to reproduce:\n1. \n\nExpected:\n\nActual:",
            keywords: ["bug", "issue", "report"]
        ),
        Snippet(
            id: "thank-you",
            title: "Thank You",
            body: "Thanks, I appreciate it.",
            keywords: ["thanks", "thank you", "reply"]
        ),
    ]
}
