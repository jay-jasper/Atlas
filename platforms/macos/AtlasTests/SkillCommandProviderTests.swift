import XCTest
@testable import Atlas

@MainActor
final class SkillCommandProviderTests: XCTestCase {
    func testReturnsNoResultsWhenFeatureDisabled() {
        let provider = SkillCommandProvider(
            store: FakeSkillStore(skills: [.screenshotSummaryExample()]),
            featureProvider: FeatureService(
                listFeatures: { [AtlasFeature(name: AtlasModule.skills.featureName, isEnabled: false)] },
                toggleFeature: { _, _ in true }
            )
        )

        XCTAssertTrue(provider.results(for: "summarize").isEmpty)
    }

    func testReturnsSkillCommandWhenFeatureEnabled() {
        let skill = SkillDefinition.screenshotSummaryExample()
        let provider = SkillCommandProvider(
            store: FakeSkillStore(skills: [skill]),
            featureProvider: FeatureService(
                listFeatures: { [AtlasFeature(name: AtlasModule.skills.featureName, isEnabled: true)] },
                toggleFeature: { _, _ in true }
            )
        )

        let results = provider.results(for: "screenshot")

        XCTAssertEqual(results.map(\.title), ["Run Summarize Screenshot"])
        XCTAssertEqual(results.first?.category, "AI Skills")
    }

    func testDoesNotScheduleInactiveBackgroundTriggersInV1() {
        let skill = SkillDefinition(
            title: "Background Clipboard Summary",
            detail: "",
            triggers: [.clipboardChanged, .screenshotCaptured],
            requiredPermissions: [.aiProvider],
            steps: [.summarizeText(prompt: "Summarize")]
        )
        let provider = SkillCommandProvider(
            store: FakeSkillStore(skills: [skill]),
            featureProvider: FeatureService(
                listFeatures: { [AtlasFeature(name: AtlasModule.skills.featureName, isEnabled: true)] },
                toggleFeature: { _, _ in true }
            )
        )

        XCTAssertTrue(provider.results(for: "clipboard").isEmpty)
    }
}

private struct FakeSkillStore: SkillStoring {
    let storedSkills: [SkillDefinition]

    init(skills: [SkillDefinition]) {
        self.storedSkills = skills
    }

    func skills() -> [SkillDefinition] {
        storedSkills
    }

    func save(_ skills: [SkillDefinition]) throws {}
    func upsert(_ skill: SkillDefinition) throws {}
    func delete(id: UUID) throws {}
}
