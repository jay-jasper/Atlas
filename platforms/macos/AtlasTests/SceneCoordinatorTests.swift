import XCTest
@testable import Atlas

final class SceneCoordinatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SceneCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCreateSceneAddsToList() {
        let coordinator = makeCoordinator()
        let before = coordinator.scenes.count
        coordinator.createScene()
        XCTAssertEqual(coordinator.scenes.count, before + 1)
    }

    func testCreateSceneActivatesNewScene() {
        let coordinator = makeCoordinator()
        coordinator.createScene()
        let newScene = coordinator.scenes.last!
        XCTAssertEqual(coordinator.activeSceneID, newScene.id)
    }

    func testDeleteSceneRemovesFromList() {
        let coordinator = makeCoordinator()
        coordinator.createScene()
        let custom = coordinator.scenes.last!
        XCTAssertFalse(custom.isBuiltIn)
        coordinator.deleteScene(custom)
        XCTAssertFalse(coordinator.scenes.contains { $0.id == custom.id })
    }

    func testDeleteBuiltInSceneIsNoop() {
        let coordinator = makeCoordinator()
        let builtIn = coordinator.scenes.first { $0.isBuiltIn }!
        let before = coordinator.scenes.count
        coordinator.deleteScene(builtIn)
        XCTAssertEqual(coordinator.scenes.count, before)
    }

    func testDuplicateSceneAppendsCopy() {
        let coordinator = makeCoordinator()
        coordinator.createScene()
        let original = coordinator.scenes.last!
        let before = coordinator.scenes.count
        coordinator.duplicateScene(original)
        XCTAssertEqual(coordinator.scenes.count, before + 1)
        let copy = coordinator.scenes.last!
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertTrue(copy.name.hasSuffix("Copy"))
        XCTAssertFalse(copy.isBuiltIn)
    }

    func testActivateSceneChangesActiveID() {
        let coordinator = makeCoordinator()
        let target = coordinator.scenes.first!
        coordinator.activateScene(id: target.id, reason: "test", isManual: true)
        XCTAssertEqual(coordinator.activeSceneID, target.id)
    }

    func testActivateSetsLastManualSceneID() {
        let coordinator = makeCoordinator()
        let target = coordinator.scenes.first!
        coordinator.activateScene(id: target.id, reason: "test", isManual: true)
        XCTAssertEqual(coordinator.lastManualSceneID, target.id)
    }

    func testUpsertSceneUpdatesExisting() {
        let coordinator = makeCoordinator()
        coordinator.createScene()
        var modified = coordinator.scenes.last!
        modified.name = "Updated"
        coordinator.upsertScene(modified)
        XCTAssertEqual(coordinator.scenes.first(where: { $0.id == modified.id })?.name, "Updated")
    }

    private func makeCoordinator() -> SceneCoordinator {
        let store = SceneStore(rootDirectory: tempDir)
        let coordinator = SceneCoordinator(store: store)
        for scene in SceneStore.defaultScenes() {
            coordinator.upsertScene(scene)
        }
        return coordinator
    }
}
