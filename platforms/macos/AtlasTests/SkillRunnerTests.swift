import Foundation
import XCTest
@testable import Atlas

final class SkillRunnerTests: XCTestCase {
    func testScreenshotToSummaryUsesInjectedProviders() async throws {
        let runner = SkillRunner(
            permissionDecisionProvider: FakePermissionDecisionProvider(decision: .allowed),
            screenshotProvider: FakeScreenshotProvider(data: Data([1, 2, 3])),
            ocrProvider: FakeOCRProvider(result: ScreenshotOCRResult(lines: ["Quarterly revenue grew 12%."])),
            aiProvider: FakeAIProvider(summary: "Revenue grew 12%."),
            automationRunner: FakeAutomationRunner(),
            emailDrafter: FakeEmailDrafter()
        )

        let result = try await runner.run(.screenshotSummaryExample())

        XCTAssertEqual(result.output, "Revenue grew 12%.")
    }

    func testAutomationStepUsesInjectedRunner() async throws {
        let automationRunner = FakeAutomationRunner(result: AutomationProcessResult(
            exitCode: 0,
            standardOutput: "script output",
            standardError: "",
            didTimeOut: false,
            duration: 0.1
        ))
        let runner = SkillRunner(
            permissionDecisionProvider: FakePermissionDecisionProvider(decision: .allowed),
            screenshotProvider: FakeScreenshotProvider(data: Data()),
            ocrProvider: FakeOCRProvider(result: ScreenshotOCRResult(lines: [])),
            aiProvider: FakeAIProvider(summary: ""),
            automationRunner: automationRunner,
            emailDrafter: FakeEmailDrafter()
        )
        let skill = SkillDefinition(
            title: "Run Build Summary Script",
            detail: "",
            triggers: [.manual],
            requiredPermissions: [.localScript],
            steps: [.runAutomation(kind: .shell, script: "echo ok", timeoutSeconds: 3)]
        )

        let result = try await runner.run(skill)

        XCTAssertEqual(result.output, "script output")
        XCTAssertEqual(automationRunner.executed.map(\.command), ["echo ok"])
    }

    func testEmailStepCreatesDraftWithoutSending() async throws {
        let emailDrafter = FakeEmailDrafter()
        let runner = SkillRunner(
            permissionDecisionProvider: FakePermissionDecisionProvider(decision: .allowed),
            screenshotProvider: FakeScreenshotProvider(data: Data([1])),
            ocrProvider: FakeOCRProvider(result: ScreenshotOCRResult(lines: ["Decision notes."])),
            aiProvider: FakeAIProvider(summary: "Short decision notes."),
            automationRunner: FakeAutomationRunner(),
            emailDrafter: emailDrafter
        )
        let skill = SkillDefinition(
            title: "Draft Summary",
            detail: "",
            triggers: [.manual],
            requiredPermissions: [.screenCapture, .aiProvider, .emailDraft],
            steps: [
                .captureScreenshot,
                .ocrScreenshot,
                .summarizeText(prompt: "Summarize"),
                .createEmailDraft(to: ["team@example.com"], subject: "Screenshot Summary")
            ]
        )

        _ = try await runner.run(skill)

        XCTAssertEqual(emailDrafter.drafts, [
            FakeEmailDrafter.Draft(to: ["team@example.com"], subject: "Screenshot Summary", body: "Short decision notes.")
        ])
    }

    func testPermissionDenialStopsBeforeAnySideEffectProviderRuns() async {
        let screenshotProvider = FakeScreenshotProvider(data: Data([1]))
        let ocrProvider = FakeOCRProvider(result: ScreenshotOCRResult(lines: ["Secret screen text."]))
        let aiProvider = FakeAIProvider(summary: "Should not run")
        let automationRunner = FakeAutomationRunner()
        let emailDrafter = FakeEmailDrafter()
        let privacyLogger = FakePrivacyAccessLogger()
        let runner = SkillRunner(
            permissionDecisionProvider: FakePermissionDecisionProvider(decision: .denied(reason: "Screen capture not approved")),
            screenshotProvider: screenshotProvider,
            ocrProvider: ocrProvider,
            aiProvider: aiProvider,
            automationRunner: automationRunner,
            emailDrafter: emailDrafter,
            privacyAccessLogger: privacyLogger
        )
        let skill = SkillDefinition(
            title: "Denied Skill",
            detail: "",
            triggers: [.manual],
            requiredPermissions: [.screenCapture, .localScript, .aiProvider, .emailDraft],
            steps: [
                .captureScreenshot,
                .ocrScreenshot,
                .summarizeText(prompt: "Summarize"),
                .runAutomation(kind: .shell, script: "echo should-not-run", timeoutSeconds: 3),
                .createEmailDraft(to: ["team@example.com"], subject: "Should Not Draft")
            ]
        )

        do {
            _ = try await runner.run(skill)
            XCTFail("Expected permission denial")
        } catch {
            XCTAssertEqual(error as? SkillRunError, .permissionDenied("Screen capture not approved"))
        }
        XCTAssertEqual(screenshotProvider.captureCount, 0)
        XCTAssertEqual(ocrProvider.recognizeCount, 0)
        XCTAssertEqual(aiProvider.summarizeCount, 0)
        XCTAssertTrue(automationRunner.executed.isEmpty)
        XCTAssertTrue(emailDrafter.drafts.isEmpty)
        XCTAssertTrue(privacyLogger.events.isEmpty)
    }

    func testPrivacyEventsAreLoggedWithoutSensitivePayloads() async throws {
        let privacyLogger = FakePrivacyAccessLogger()
        let runner = SkillRunner(
            permissionDecisionProvider: FakePermissionDecisionProvider(decision: .allowed),
            screenshotProvider: FakeScreenshotProvider(data: Data([1, 2, 3])),
            ocrProvider: FakeOCRProvider(result: ScreenshotOCRResult(lines: ["Sensitive OCR text."])),
            aiProvider: FakeAIProvider(summary: "Sensitive summary."),
            automationRunner: FakeAutomationRunner(result: AutomationProcessResult(
                exitCode: 0,
                standardOutput: "Sensitive script output.",
                standardError: "",
                didTimeOut: false,
                duration: 0.1
            )),
            emailDrafter: FakeEmailDrafter(),
            privacyAccessLogger: privacyLogger
        )
        let skill = SkillDefinition(
            title: "Privacy Audit",
            detail: "",
            triggers: [.manual],
            requiredPermissions: [.screenCapture, .localScript, .aiProvider, .emailDraft],
            steps: [
                .captureScreenshot,
                .ocrScreenshot,
                .summarizeText(prompt: "Do not log this prompt"),
                .runAutomation(kind: .shell, script: "echo do-not-log", timeoutSeconds: 3),
                .createEmailDraft(to: ["private@example.com"], subject: "Private Subject")
            ]
        )

        _ = try await runner.run(skill)

        XCTAssertEqual(privacyLogger.events.map(\.kind), [.screenCapture, .localAutomation, .emailDraft])
        XCTAssertTrue(privacyLogger.events.allSatisfy { $0.skillID == skill.id && $0.skillTitle == "Privacy Audit" })
        XCTAssertFalse(privacyLogger.serializedEventsForAssertion.contains("Sensitive OCR text"))
        XCTAssertFalse(privacyLogger.serializedEventsForAssertion.contains("Sensitive summary"))
        XCTAssertFalse(privacyLogger.serializedEventsForAssertion.contains("do-not-log"))
        XCTAssertFalse(privacyLogger.serializedEventsForAssertion.contains("private@example.com"))
        XCTAssertFalse(privacyLogger.serializedEventsForAssertion.contains("Private Subject"))
    }
}

private struct FakePermissionDecisionProvider: SkillPermissionDecisionProviding {
    let result: SkillPermissionDecision

    init(decision: SkillPermissionDecision) {
        self.result = decision
    }

    func decision(for permissions: [SkillPermission], skill: SkillDefinition) -> SkillPermissionDecision {
        result
    }
}

private final class FakeScreenshotProvider: ScreenshotImageProviding {
    let data: Data
    private(set) var captureCount = 0

    init(data: Data) {
        self.data = data
    }

    func captureScreenshotData() throws -> Data {
        captureCount += 1
        return data
    }
}

private final class FakeOCRProvider: ScreenshotOCRProviding {
    let result: ScreenshotOCRResult
    private(set) var recognizeCount = 0

    init(result: ScreenshotOCRResult) {
        self.result = result
    }

    func recognizeText(in imageData: Data) throws -> ScreenshotOCRResult {
        recognizeCount += 1
        return result
    }
}

private final class FakeAIProvider: SkillAIProviding {
    let summary: String
    private(set) var summarizeCount = 0

    init(summary: String) {
        self.summary = summary
    }

    func summarize(text: String, prompt: String) async throws -> String {
        summarizeCount += 1
        return summary
    }
}

private final class FakeAutomationRunner: AutomationProcessRunning {
    var executed: [CustomAutomationCommand] = []
    let result: AutomationProcessResult

    init(result: AutomationProcessResult = AutomationProcessResult(
        exitCode: 0,
        standardOutput: "",
        standardError: "",
        didTimeOut: false,
        duration: 0
    )) {
        self.result = result
    }

    func run(_ command: CustomAutomationCommand) async -> AutomationProcessResult {
        executed.append(command)
        return result
    }
}

private final class FakeEmailDrafter: EmailDrafting {
    struct Draft: Equatable {
        let to: [String]
        let subject: String
        let body: String
    }

    var drafts: [Draft] = []

    func createDraft(to: [String], subject: String, body: String) throws {
        drafts.append(Draft(to: to, subject: subject, body: body))
    }
}

private final class FakePrivacyAccessLogger: SkillPrivacyAccessLogging {
    struct Event: Equatable {
        let kind: SkillPrivacyAccessKind
        let skillID: UUID
        let skillTitle: String
    }

    var events: [Event] = []

    var serializedEventsForAssertion: String {
        events.map { "\($0.kind.rawValue)|\($0.skillID.uuidString)|\($0.skillTitle)" }.joined(separator: "\n")
    }

    func logAccess(kind: SkillPrivacyAccessKind, skillID: UUID, skillTitle: String) {
        events.append(Event(kind: kind, skillID: skillID, skillTitle: skillTitle))
    }
}
