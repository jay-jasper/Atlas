import Foundation

struct ScratchpadNote: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var markdown: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        markdown: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.markdown = markdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ScratchpadDraft: Equatable {
    var title: String
    var markdown: String

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedMarkdown: String {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !normalizedTitle.isEmpty || !normalizedMarkdown.isEmpty
    }
}

enum ScratchpadStoreError: LocalizedError, Equatable {
    case invalidDraft
    case noteNotFound

    var errorDescription: String? {
        switch self {
        case .invalidDraft:
            return "Scratchpad notes require a title or Markdown body."
        case .noteNotFound:
            return "Scratchpad note was not found."
        }
    }
}
