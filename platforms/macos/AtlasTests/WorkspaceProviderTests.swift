import XCTest
@testable import Atlas

final class WorkspaceProviderTests: XCTestCase {
    func testDisabledProviderReturnsNoResults() {
        let provider = WorkspaceProvider(store: FakeWorkspaceProviderStore(), isEnabled: { false })

        XCTAssertTrue(provider.results(for: "workspace").isEmpty)
    }

    func testWorkspaceQueryReturnsOpenAndSaveActions() {
        let provider = WorkspaceProvider(store: FakeWorkspaceProviderStore(), isEnabled: { true })

        let results = provider.results(for: "workspace")

        XCTAssertEqual(results.map(\.title), ["Open Workspaces", "Save Current Workspace"])
    }

    func testSavedWorkspaceAppearsAsRestoreAction() {
        let store = FakeWorkspaceProviderStore()
        store.workspaces = [workspace(name: "Writing")]
        let provider = WorkspaceProvider(store: store, isEnabled: { true })

        let results = provider.results(for: "writing")

        XCTAssertEqual(results.map(\.title), ["Restore Workspace: Writing"])
    }

    func testOpenActionDispatchesPanelCallback() {
        let provider = WorkspaceProvider(
            store: FakeWorkspaceProviderStore(),
            isEnabled: { true }
        )

        let command = provider.results(for: "open workspaces").first

        if case .push(.workspaces)? = command?.action {
            XCTAssertEqual(command?.title, "Open Workspaces")
        } else {
            XCTFail("expected Open Workspaces to push the workspaces destination")
        }
    }

    func testSaveActionDispatchesSaveCallback() {
        var saveCount = 0
        let provider = WorkspaceProvider(
            store: FakeWorkspaceProviderStore(),
            isEnabled: { true },
            onSaveCurrent: { saveCount += 1 }
        )

        execute(provider.results(for: "save current workspace").first)

        XCTAssertEqual(saveCount, 1)
    }

    func testRestoreActionDispatchesWorkspaceCallback() {
        let store = FakeWorkspaceProviderStore()
        let saved = workspace(name: "Writing")
        store.workspaces = [saved]
        var restored: [Workspace] = []
        let provider = WorkspaceProvider(
            store: store,
            isEnabled: { true },
            onRestore: { restored.append($0) }
        )

        execute(provider.results(for: "writing").first)

        XCTAssertEqual(restored, [saved])
    }

    private func execute(_ command: PaletteCommand?) {
        if case .execute(let action)? = command?.action {
            action()
        } else {
            XCTFail("expected execute action")
        }
    }
}

private final class FakeWorkspaceProviderStore: WorkspaceStoring {
    var workspaces: [Workspace] = []

    func load() throws -> [Workspace] {
        workspaces
    }

    func save(_ workspace: Workspace) throws {
        workspaces.append(workspace)
    }

    func delete(id: UUID) throws {
        workspaces.removeAll { $0.id == id }
    }
}

private func workspace(name: String) -> Workspace {
    Workspace(id: UUID(), name: name, createdAt: Date(), updatedAt: Date(), windows: [])
}
