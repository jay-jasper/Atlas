import XCTest
@testable import Atlas

@MainActor
final class AudioPresetStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioPresetStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadReturnsEmptyWhenFileAbsent() {
        XCTAssertEqual(makeStore().load(), [])
    }

    func testSaveAndLoadRoundTrip() {
        let store = makeStore()
        let preset = AudioPreset(title: "Work Setup", outputDeviceID: 42, inputDeviceID: 7)
        store.save([preset])
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "Work Setup")
        XCTAssertEqual(loaded[0].outputDeviceID, 42)
        XCTAssertEqual(loaded[0].inputDeviceID, 7)
    }

    func testSaveOverwritesPreviousPresets() {
        let store = makeStore()
        store.save([AudioPreset(title: "Old", outputDeviceID: 1, inputDeviceID: nil)])
        store.save([AudioPreset(title: "New", outputDeviceID: 2, inputDeviceID: nil)])
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "New")
    }

    func testSaveEmptyListClearsPresets() {
        let store = makeStore()
        store.save([AudioPreset(title: "Preset", outputDeviceID: 1, inputDeviceID: nil)])
        store.save([])
        XCTAssertEqual(store.load(), [])
    }

    private func makeStore() -> AudioPresetStore {
        AudioPresetStore(url: tempDir.appendingPathComponent("presets.json"))
    }
}
