import XCTest
@testable import Atlas

final class SceneStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SceneStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadScenesCreatesDefaultsWhenFileAbsent() throws {
        let store = makeStore()
        let scenes = try store.loadScenes()
        XCTAssertFalse(scenes.isEmpty)
        XCTAssertTrue(scenes.allSatisfy(\.isBuiltIn))
    }

    func testSaveAndLoadRoundTrip() throws {
        let store = makeStore()
        let original = try store.loadScenes()
        var modified = original
        modified[0].name = "Renamed"
        try store.saveScenes(modified)

        let reloaded = try store.loadScenes()
        XCTAssertEqual(reloaded[0].name, "Renamed")
    }

    func testMergedWithDefaultsPreservesUnknownUserScenes() throws {
        let store = makeStore()
        var scenes = try store.loadScenes()
        let custom = SceneDefinition(name: "Custom", isBuiltIn: false)
        scenes.append(custom)
        try store.saveScenes(scenes)

        let reloaded = try store.loadScenes()
        XCTAssertTrue(reloaded.contains { $0.id == custom.id })
    }

    func testLoadRuntimeStateReturnsDefaultWhenAbsent() {
        let state = makeStore().loadRuntimeState()
        XCTAssertNotNil(state.activeSceneID)
    }

    func testSaveAndLoadRuntimeStateRoundTrip() throws {
        let store = makeStore()
        let sceneID = UUID()
        let state = SceneRuntimeState(activeSceneID: sceneID, lastManualSceneID: nil)
        try store.saveRuntimeState(state)

        let loaded = store.loadRuntimeState()
        XCTAssertEqual(loaded.activeSceneID, sceneID)
    }

    func testAppendHistoryCappsAtMax() throws {
        let store = makeStore()
        for i in 0..<5 {
            let record = SceneExecutionRecord(
                sceneID: UUID(),
                sceneName: "Scene \(i)",
                reason: "test",
                status: .success,
                detail: ""
            )
            try store.appendHistory(record, maxCount: 3)
        }
        let history = store.loadHistory()
        XCTAssertEqual(history.count, 3)
    }

    func testLoadHistoryReturnsEmptyWhenAbsent() {
        XCTAssertEqual(makeStore().loadHistory(), [])
    }

    private func makeStore() -> SceneStore {
        SceneStore(rootDirectory: tempDir)
    }
}
