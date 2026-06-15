import XCTest
@testable import Atlas

@MainActor
final class SceneResolverTests: XCTestCase {
    func testResolveReturnsNilForUnknownID() {
        XCTAssertNil(SceneResolver.resolve(sceneID: UUID(), scenes: []))
    }

    func testResolveWithNoInheritanceReturnsScenesOwnOverrides() {
        let override = SceneModuleOverride(moduleID: .screenshot, state: .enabled)
        let scene = SceneDefinition(name: "Test", moduleOverrides: [override])
        let result = SceneResolver.resolve(sceneID: scene.id, scenes: [scene])
        XCTAssertEqual(result?.moduleOverrides, [override])
    }

    func testResolveAppendsActionsOnAppendPolicy() {
        let parentAction = makeAction("parent")
        let childAction = makeAction("child")
        let parent = SceneDefinition(name: "Parent", onEnter: [parentAction])
        let child = SceneDefinition(name: "Child", extends: parent.id, mergePolicy: .append, onEnter: [childAction])

        let result = SceneResolver.resolve(sceneID: child.id, scenes: [parent, child])
        XCTAssertEqual(result?.onEnter.map(\.id), [parentAction.id, childAction.id])
    }

    func testResolveChildOverridesParentActionsOnReplacePolicy() {
        let parentAction = makeAction("parent")
        let childAction = makeAction("child")
        let parent = SceneDefinition(name: "Parent", onEnter: [parentAction])
        let child = SceneDefinition(name: "Child", extends: parent.id, mergePolicy: .replace, onEnter: [childAction])

        let result = SceneResolver.resolve(sceneID: child.id, scenes: [parent, child])
        XCTAssertEqual(result?.onEnter.map(\.id), [childAction.id])
    }

    func testResolveUsesParentActionsWhenChildHasNoneOnReplace() {
        let parentAction = makeAction("parent")
        let parent = SceneDefinition(name: "Parent", onEnter: [parentAction])
        let child = SceneDefinition(name: "Child", extends: parent.id, mergePolicy: .replace, onEnter: [])

        let result = SceneResolver.resolve(sceneID: child.id, scenes: [parent, child])
        XCTAssertEqual(result?.onEnter.map(\.id), [parentAction.id])
    }

    func testResolveMergesModuleOverridesOnExplicitDisablePolicy() {
        let parentOverride = SceneModuleOverride(moduleID: .screenshot, state: .enabled)
        let childOverride = SceneModuleOverride(moduleID: .monitoring, state: .disabled, visibility: .hidden)
        let parent = SceneDefinition(name: "Parent", moduleOverrides: [parentOverride])
        let child = SceneDefinition(name: "Child", extends: parent.id, mergePolicy: .explicitDisable, moduleOverrides: [childOverride])

        let result = SceneResolver.resolve(sceneID: child.id, scenes: [parent, child])
        let ids = result?.moduleOverrides.map(\.moduleID) ?? []
        XCTAssertTrue(ids.contains(.screenshot))
        XCTAssertTrue(ids.contains(.monitoring))
    }

    func testResolveBehaviorRulesPreservesParentNonDefaultOnAppend() {
        let parent = SceneDefinition(
            name: "Parent",
            behaviorRules: SceneBehaviorRules(
                newScreenshotsGoToInbox: false,
                preferInboxFavorites: false,
                prioritizeRecentContent: true,
                promoteCommandPaletteCategory: "custom"
            )
        )
        let child = SceneDefinition(
            name: "Child",
            extends: parent.id,
            mergePolicy: .append,
            behaviorRules: .default
        )

        let result = SceneResolver.resolve(sceneID: child.id, scenes: [parent, child])
        XCTAssertEqual(result?.behaviorRules.promoteCommandPaletteCategory, "custom")
    }

    private func makeAction(_ title: String) -> SceneAction {
        SceneAction(title: title, type: .atlasAction)
    }
}
