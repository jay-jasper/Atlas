import Foundation

enum CustomAutomationKind: String, Codable, Equatable, CaseIterable, Sendable {
    case shell
    case python

    var title: String {
        switch self {
        case .shell:
            return "Shell"
        case .python:
            return "Python"
        }
    }
}

struct CustomAutomationCommand: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var command: String
    var kind: CustomAutomationKind
    var keywords: [String]
    var timeoutSeconds: TimeInterval
    var requiresConfirmation: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        command: String,
        kind: CustomAutomationKind,
        keywords: [String] = [],
        timeoutSeconds: TimeInterval = 10,
        requiresConfirmation: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.command = command
        self.kind = kind
        self.keywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.timeoutSeconds = timeoutSeconds
        self.requiresConfirmation = requiresConfirmation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isValid: Bool {
        !title.isEmpty && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && timeoutSeconds > 0
    }
}
