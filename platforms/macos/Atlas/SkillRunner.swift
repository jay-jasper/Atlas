import AppKit
import Foundation

protocol ScreenshotImageProviding {
    func captureScreenshotData() throws -> Data
}

protocol SkillAIProviding {
    func summarize(text: String, prompt: String) async throws -> String
}

protocol EmailDrafting {
    func createDraft(to: [String], subject: String, body: String) throws
}

enum SkillPermissionDecision: Equatable, Sendable {
    case allowed
    case denied(reason: String)
}

protocol SkillPermissionDecisionProviding {
    func decision(for permissions: [SkillPermission], skill: SkillDefinition) -> SkillPermissionDecision
}

struct AllowAllSkillPermissionDecisionProvider: SkillPermissionDecisionProviding {
    func decision(for permissions: [SkillPermission], skill: SkillDefinition) -> SkillPermissionDecision {
        .allowed
    }
}

enum SkillPrivacyAccessKind: String, Sendable {
    case screenCapture
    case localAutomation
    case emailDraft
}

protocol SkillPrivacyAccessLogging {
    func logAccess(kind: SkillPrivacyAccessKind, skillID: UUID, skillTitle: String)
}

struct NoOpSkillPrivacyAccessLogger: SkillPrivacyAccessLogging {
    func logAccess(kind: SkillPrivacyAccessKind, skillID: UUID, skillTitle: String) {}
}

enum SkillRunError: LocalizedError, Equatable {
    case disabled
    case permissionDenied(String)
    case missingScreenshot
    case missingText
    case automationFailed(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "This skill is disabled."
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .missingScreenshot:
            return "The skill needs a screenshot before OCR can run."
        case .missingText:
            return "The skill needs text before it can summarize or draft email."
        case .automationFailed(let message):
            return "Automation failed: \(message)"
        }
    }
}

struct SkillRunner {
    private let permissionDecisionProvider: SkillPermissionDecisionProviding
    private let screenshotProvider: ScreenshotImageProviding
    private let ocrProvider: ScreenshotOCRProviding
    private let aiProvider: SkillAIProviding
    private let automationRunner: AutomationProcessRunning
    private let emailDrafter: EmailDrafting
    private let privacyAccessLogger: SkillPrivacyAccessLogging

    init(
        permissionDecisionProvider: SkillPermissionDecisionProviding,
        screenshotProvider: ScreenshotImageProviding,
        ocrProvider: ScreenshotOCRProviding,
        aiProvider: SkillAIProviding,
        automationRunner: AutomationProcessRunning,
        emailDrafter: EmailDrafting,
        privacyAccessLogger: SkillPrivacyAccessLogging = NoOpSkillPrivacyAccessLogger()
    ) {
        self.permissionDecisionProvider = permissionDecisionProvider
        self.screenshotProvider = screenshotProvider
        self.ocrProvider = ocrProvider
        self.aiProvider = aiProvider
        self.automationRunner = automationRunner
        self.emailDrafter = emailDrafter
        self.privacyAccessLogger = privacyAccessLogger
    }

    func run(_ skill: SkillDefinition) async throws -> SkillRunResult {
        guard skill.isEnabled else {
            throw SkillRunError.disabled
        }
        switch permissionDecisionProvider.decision(for: skill.requiredPermissions, skill: skill) {
        case .allowed:
            break
        case .denied(let reason):
            throw SkillRunError.permissionDenied(reason)
        }

        var screenshotData: Data?
        var text = ""
        var output = ""

        for step in skill.steps {
            switch step {
            case .captureScreenshot:
                privacyAccessLogger.logAccess(kind: .screenCapture, skillID: skill.id, skillTitle: skill.title)
                screenshotData = try screenshotProvider.captureScreenshotData()
            case .ocrScreenshot:
                guard let screenshotData else {
                    throw SkillRunError.missingScreenshot
                }
                text = try ocrProvider.recognizeText(in: screenshotData).text
                output = text
            case .summarizeText(let prompt):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SkillRunError.missingText
                }
                output = try await aiProvider.summarize(text: text, prompt: prompt)
                text = output
            case .runAutomation(let kind, let script, let timeoutSeconds):
                privacyAccessLogger.logAccess(kind: .localAutomation, skillID: skill.id, skillTitle: skill.title)
                let command = CustomAutomationCommand(
                    title: "\(skill.title) Automation Step",
                    command: script,
                    kind: kind,
                    timeoutSeconds: timeoutSeconds,
                    requiresConfirmation: true
                )
                let result = await automationRunner.run(command)
                guard result.exitCode == 0 else {
                    throw SkillRunError.automationFailed(result.standardError.isEmpty ? "exit \(result.exitCode)" : result.standardError)
                }
                output = result.standardOutput
                if !result.standardOutput.isEmpty {
                    text = result.standardOutput
                }
            case .createEmailDraft(let to, let subject):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SkillRunError.missingText
                }
                privacyAccessLogger.logAccess(kind: .emailDraft, skillID: skill.id, skillTitle: skill.title)
                try emailDrafter.createDraft(to: to, subject: subject, body: text)
                output = "Draft created: \(subject)"
            }
        }

        return SkillRunResult(skillID: skill.id, title: skill.title, output: output)
    }
}

enum SkillRuntimeFactory {
    static func makeDefaultRunner() -> SkillRunner {
        SkillRunner(
            permissionDecisionProvider: AppSkillPermissionDecisionProvider(),
            screenshotProvider: LiveScreenshotImageProvider(),
            ocrProvider: VisionScreenshotOCRService(),
            aiProvider: UnconfiguredSkillAIProvider(),
            automationRunner: SystemAutomationProcessRunner(),
            emailDrafter: LocalEmailDraftService(),
            privacyAccessLogger: SkillPrivacyAccessLoggerFactory.makeDefault()
        )
    }
}

struct AppSkillPermissionDecisionProvider: SkillPermissionDecisionProviding {
    var grantedPermissions: () -> Set<SkillPermission> = { [] }

    func decision(for permissions: [SkillPermission], skill: SkillDefinition) -> SkillPermissionDecision {
        let granted = grantedPermissions()
        let denied = permissions.filter { !granted.contains($0) }
        guard denied.isEmpty else {
            return .denied(reason: denied.map(\.title).joined(separator: ", "))
        }
        return .allowed
    }
}

enum SkillPrivacyAccessLoggerFactory {
    static func makeDefault() -> SkillPrivacyAccessLogging {
        NoOpSkillPrivacyAccessLogger()
    }
}

struct LiveScreenshotImageProvider: ScreenshotImageProviding {
    func captureScreenshotData() throws -> Data {
        try AtlasCaptureService.live.captureFullScreen()
    }
}

struct UnconfiguredSkillAIProvider: SkillAIProviding {
    func summarize(text: String, prompt: String) async throws -> String {
        throw ScreenshotTranslationError.providerFailed("AI Skills provider is not configured.")
    }
}

struct LocalEmailDraftService: EmailDrafting {
    func createDraft(to: [String], subject: String, body: String) throws {
        let service = NSSharingService(named: .composeEmail)
        service?.recipients = to
        service?.subject = subject
        service?.perform(withItems: [body])
    }
}
