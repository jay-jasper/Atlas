import XCTest
@testable import Atlas

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("workspaces.json")
    }

    func testSaveAndLoadWorkspace() throws {
        let store = WorkspaceStore(fileURL: fileURL)
        let workspace = makeWorkspace(id: "00000000-0000-0000-0000-000000000001", name: "Dev")

        try store.save(workspace)

        XCTAssertEqual(try store.load(), [workspace])
    }

    func testSavingSameIDReplacesExistingWorkspaceAndSortsByUpdatedAtDescending() throws {
        let store = WorkspaceStore(fileURL: fileURL)
        let first = makeWorkspace(id: "00000000-0000-0000-0000-000000000001", name: "First", updatedAt: 10)
        let replacement = makeWorkspace(id: "00000000-0000-0000-0000-000000000001", name: "Replacement", updatedAt: 30)
        let second = makeWorkspace(id: "00000000-0000-0000-0000-000000000002", name: "Second", updatedAt: 20)

        try store.save(first)
        try store.save(second)
        try store.save(replacement)

        XCTAssertEqual(try store.load().map(\.name), ["Replacement", "Second"])
    }

    func testDeleteWorkspaceRemovesMatchingID() throws {
        let store = WorkspaceStore(fileURL: fileURL)
        let first = makeWorkspace(id: "00000000-0000-0000-0000-000000000001", name: "First")
        let second = makeWorkspace(id: "00000000-0000-0000-0000-000000000002", name: "Second")
        try store.save(first)
        try store.save(second)

        try store.delete(id: first.id)

        XCTAssertEqual(try store.load(), [second])
    }

    private func makeWorkspace(
        id: String,
        name: String,
        updatedAt: TimeInterval = 20
    ) -> Workspace {
        Workspace(
            id: UUID(uuidString: id)!,
            name: name,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            windows: []
        )
    }
}
