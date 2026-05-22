import XCTest
@testable import Atlas

final class SkillModelsTests: XCTestCase {
    func testScreenshotSummaryExampleContainsExpectedMetadata() {
        let skill = SkillDefinition.screenshotSummaryExample(now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(skill.title, "Summarize Screenshot")
        XCTAssertEqual(skill.triggers, [.manual, .commandPalette(keyword: "summarize screenshot")])
        XCTAssertEqual(skill.requiredPermissions, [.aiProvider, .screenCapture])
        XCTAssertEqual(skill.steps, [
            .captureScreenshot,
            .ocrScreenshot,
            .summarizeText(prompt: "Summarize the screenshot text in three concise bullets.")
        ])
    }

    func testSkillRoundTripsThroughJSON() throws {
        let skill = SkillDefinition(
            title: "Daily Summary",
            detail: "Summarize text and draft email.",
            triggers: [.manual],
            requiredPermissions: [.aiProvider, .emailDraft],
            steps: [
                .summarizeText(prompt: "Summarize"),
                .createEmailDraft(to: ["team@example.com"], subject: "Summary")
            ],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(SkillDefinition.self, from: try encoder.encode(skill))

        XCTAssertEqual(decoded, skill)
    }

    func testBackgroundTriggerTypesAreStoredButInactiveInV1() {
        XCTAssertTrue(SkillTrigger.manual.isActiveInV1)
        XCTAssertTrue(SkillTrigger.commandPalette(keyword: "summarize").isActiveInV1)
        XCTAssertFalse(SkillTrigger.screenshotCaptured.isActiveInV1)
        XCTAssertFalse(SkillTrigger.clipboardChanged.isActiveInV1)
        XCTAssertEqual(SkillTrigger.screenshotCaptured.v1StatusTitle, "Planned")
        XCTAssertEqual(SkillTrigger.clipboardChanged.v1StatusTitle, "Planned")
    }
}
