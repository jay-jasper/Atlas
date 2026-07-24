import XCTest
@testable import Atlas

@MainActor
final class PluginSandboxTests: XCTestCase {
    func testStoreBuildDisablesExecutablePluginPlatform() {
        XCTAssertFalse(DistributionPolicy.allowsExecutablePluginsForStore)
    }

    func testExternalFileRequiresIssuedBookmarkHandle() throws {
        let store = InMemoryPluginBookmarkStore()
        let adapter = PluginFileAdapter(bookmarkStore: store)

        XCTAssertThrowsError(try adapter.read(pluginID: "dev.example.a", handle: UUID().uuidString))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("allowed".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let handle = try adapter.issue(pluginID: "dev.example.a", url: file)
        XCTAssertEqual(try adapter.read(pluginID: "dev.example.a", handle: handle), Data("allowed".utf8))
        XCTAssertThrowsError(try adapter.read(pluginID: "dev.example.b", handle: handle))
    }
}

private final class InMemoryPluginBookmarkStore: PluginBookmarkStoring {
    private var records: [String: URL] = [:]

    func issue(pluginID: String, url: URL) throws -> String {
        let handle = UUID().uuidString
        records["\(pluginID):\(handle)"] = url
        return handle
    }

    func resolve(pluginID: String, handle: String) throws -> URL {
        guard let url = records["\(pluginID):\(handle)"] else {
            throw PluginPlatformAdapterError.invalidBookmark
        }
        return url
    }
}
