import Foundation

enum SkillTrigger: Codable, Equatable, Sendable {
    case manual
    case commandPalette(keyword: String)
    case screenshotCaptured
    case clipboardChanged

    private enum CodingKeys: String, CodingKey {
        case type
        case keyword
    }

    private enum TriggerType: String, Codable {
        case manual
        case commandPalette
        case screenshotCaptured
        case clipboardChanged
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TriggerType.self, forKey: .type)
        switch type {
        case .manual:
            self = .manual
        case .commandPalette:
            self = .commandPalette(keyword: try container.decode(String.self, forKey: .keyword))
        case .screenshotCaptured:
            self = .screenshotCaptured
        case .clipboardChanged:
            self = .clipboardChanged
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manual:
            try container.encode(TriggerType.manual, forKey: .type)
        case .commandPalette(let keyword):
            try container.encode(TriggerType.commandPalette, forKey: .type)
            try container.encode(keyword, forKey: .keyword)
        case .screenshotCaptured:
            try container.encode(TriggerType.screenshotCaptured, forKey: .type)
        case .clipboardChanged:
            try container.encode(TriggerType.clipboardChanged, forKey: .type)
        }
    }

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .commandPalette:
            return "Command Palette"
        case .screenshotCaptured:
            return "Screenshot Captured"
        case .clipboardChanged:
            return "Clipboard Changed"
        }
    }

    var isActiveInV1: Bool {
        switch self {
        case .manual, .commandPalette:
            return true
        case .screenshotCaptured, .clipboardChanged:
            return false
        }
    }

    var v1StatusTitle: String {
        isActiveInV1 ? "Enabled" : "Planned"
    }
}

enum SkillPermission: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case screenCapture
    case localScript
    case aiProvider
    case emailDraft
    case fileRead
    case fileWrite

    var title: String {
        switch self {
        case .screenCapture:
            return "Screen Capture"
        case .localScript:
            return "Local Script"
        case .aiProvider:
            return "AI Provider"
        case .emailDraft:
            return "Email Draft"
        case .fileRead:
            return "File Read"
        case .fileWrite:
            return "File Write"
        }
    }
}

enum SkillStep: Codable, Equatable, Sendable {
    case captureScreenshot
    case ocrScreenshot
    case summarizeText(prompt: String)
    case runAutomation(kind: CustomAutomationKind, script: String, timeoutSeconds: TimeInterval)
    case createEmailDraft(to: [String], subject: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case prompt
        case kind
        case script
        case timeoutSeconds
        case to
        case subject
    }

    private enum StepType: String, Codable {
        case captureScreenshot
        case ocrScreenshot
        case summarizeText
        case runAutomation
        case createEmailDraft
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepType.self, forKey: .type)
        switch type {
        case .captureScreenshot:
            self = .captureScreenshot
        case .ocrScreenshot:
            self = .ocrScreenshot
        case .summarizeText:
            self = .summarizeText(prompt: try container.decode(String.self, forKey: .prompt))
        case .runAutomation:
            self = .runAutomation(
                kind: try container.decode(CustomAutomationKind.self, forKey: .kind),
                script: try container.decode(String.self, forKey: .script),
                timeoutSeconds: try container.decode(TimeInterval.self, forKey: .timeoutSeconds)
            )
        case .createEmailDraft:
            self = .createEmailDraft(
                to: try container.decode([String].self, forKey: .to),
                subject: try container.decode(String.self, forKey: .subject)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .captureScreenshot:
            try container.encode(StepType.captureScreenshot, forKey: .type)
        case .ocrScreenshot:
            try container.encode(StepType.ocrScreenshot, forKey: .type)
        case .summarizeText(let prompt):
            try container.encode(StepType.summarizeText, forKey: .type)
            try container.encode(prompt, forKey: .prompt)
        case .runAutomation(let kind, let script, let timeoutSeconds):
            try container.encode(StepType.runAutomation, forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encode(script, forKey: .script)
            try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        case .createEmailDraft(let to, let subject):
            try container.encode(StepType.createEmailDraft, forKey: .type)
            try container.encode(to, forKey: .to)
            try container.encode(subject, forKey: .subject)
        }
    }
}

struct SkillDefinition: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var detail: String
    var triggers: [SkillTrigger]
    var requiredPermissions: [SkillPermission]
    var steps: [SkillStep]
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        triggers: [SkillTrigger],
        requiredPermissions: [SkillPermission],
        steps: [SkillStep],
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.triggers = triggers
        self.requiredPermissions = Array(Set(requiredPermissions)).sorted { $0.rawValue < $1.rawValue }
        self.steps = steps
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isValid: Bool {
        !title.isEmpty && !steps.isEmpty && !triggers.isEmpty
    }

    static func screenshotSummaryExample(now: Date = Date()) -> SkillDefinition {
        SkillDefinition(
            title: "Summarize Screenshot",
            detail: "Capture the screen, extract text, and summarize it.",
            triggers: [.manual, .commandPalette(keyword: "summarize screenshot")],
            requiredPermissions: [.screenCapture, .aiProvider],
            steps: [
                .captureScreenshot,
                .ocrScreenshot,
                .summarizeText(prompt: "Summarize the screenshot text in three concise bullets.")
            ],
            createdAt: now,
            updatedAt: now
        )
    }
}

struct SkillRunResult: Equatable, Sendable {
    let skillID: UUID
    let title: String
    let output: String
}
