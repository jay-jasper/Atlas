import XCTest
@testable import Atlas

final class SkillStoreTests: XCTestCase {
    func testEmptyStoreReturnsScreenshotSummaryExample() {
        let store = SkillStore(fileURL: temporaryFileURL())

        let skills = store.skills()

        XCTAssertEqual(skills.map(\.title), ["Summarize Screenshot"])
    }

    func testSaveAndLoadSkills() throws {
        let url = temporaryFileURL()
        let store = SkillStore(fileURL: url)
        let skill = SkillDefinition(
            title: "Build Notes",
            detail: "Summarize build output.",
            triggers: [.manual],
            requiredPermissions: [.aiProvider],
            steps: [.summarizeText(prompt: "Summarize build output.")],
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        try store.save([skill])

        XCTAssertEqual(SkillStore(fileURL: url).skills(), [skill])
    }

    func testRejectsDuplicateTitles() {
        let store = SkillStore(fileURL: temporaryFileURL())
        let first = SkillDefinition(title: "Duplicate", detail: "", triggers: [.manual], requiredPermissions: [], steps: [.summarizeText(prompt: "A")])
        let second = SkillDefinition(title: "duplicate", detail: "", triggers: [.manual], requiredPermissions: [], steps: [.summarizeText(prompt: "B")])

        XCTAssertThrowsError(try store.save([first, second])) { error in
            XCTAssertEqual(error as? SkillStoreError, .duplicateTitle)
        }
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("skills.json")
    }
}
