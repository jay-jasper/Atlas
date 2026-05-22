import XCTest
@testable import Atlas

@MainActor
final class WorkspacePanelTests: XCTestCase {
    func testSaveCurrentLayoutStoresCapturedWorkspace() throws {
        let store = FakeWorkspaceStore()
        let service = WorkspaceWindowService(
            snapshotProvider: FakeWorkspaceSnapshots(windows: [workspaceWindow("Editor")]),
            restorer: FakeWorkspaceRestore()
        )
        let permission = FakeWorkspacePermissionChecker(isTrusted: true)
        let model = WorkspacePanelModel(
            store: store,
            service: service,
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        try model.saveCurrentLayout(named: "Coding")

        XCTAssertEqual(store.savedWorkspaces.map(\.name), ["Coding"])
        XCTAssertEqual(model.workspaces.map(\.name), ["Coding"])
    }

    func testSaveCurrentLayoutDoesNotCaptureWhenFeatureDisabled() throws {
        let store = FakeWorkspaceStore()
        let service = WorkspaceWindowService(
            snapshotProvider: FakeWorkspaceSnapshots(windows: [workspaceWindow("Editor")]),
            restorer: FakeWorkspaceRestore()
        )
        let permission = FakeWorkspacePermissionChecker(isTrusted: true)
        let model = WorkspacePanelModel(
            store: store,
            service: service,
            permissionChecker: permission,
            isFeatureEnabled: { false }
        )

        try model.saveCurrentLayout(named: "Coding")

        XCTAssertTrue(store.savedWorkspaces.isEmpty)
        XCTAssertEqual(model.statusMessage, "Window Manager is disabled")
    }

    func testSaveCurrentLayoutRequestsPermissionWhenAccessibilityIsNotTrusted() throws {
        let store = FakeWorkspaceStore()
        let service = WorkspaceWindowService(
            snapshotProvider: FakeWorkspaceSnapshots(windows: [workspaceWindow("Editor")]),
            restorer: FakeWorkspaceRestore()
        )
        let permission = FakeWorkspacePermissionChecker(isTrusted: false)
        let model = WorkspacePanelModel(
            store: store,
            service: service,
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        try model.saveCurrentLayout(named: "Coding")

        XCTAssertTrue(store.savedWorkspaces.isEmpty)
        XCTAssertEqual(permission.requestCount, 1)
        XCTAssertEqual(model.statusMessage, "Accessibility permission is required")
    }

    func testRestoreRecordsMissingWindowMessage() throws {
        let store = FakeWorkspaceStore()
        let missing = workspaceWindow("Missing")
        let workspace = Workspace(id: UUID(), name: "Coding", createdAt: Date(), updatedAt: Date(), windows: [missing])
        store.workspaces = [workspace]
        let restore = FakeWorkspaceRestore(report: WorkspaceRestoreReport(
            restoredWindows: [],
            issues: [WorkspaceRestoreIssue(window: missing, reason: .windowNotFound)]
        ))
        let service = WorkspaceWindowService(
            snapshotProvider: FakeWorkspaceSnapshots(windows: []),
            restorer: restore
        )
        let permission = FakeWorkspacePermissionChecker(isTrusted: true)
        let model = WorkspacePanelModel(
            store: store,
            service: service,
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )
        try model.reload()

        try model.restore(workspace)

        XCTAssertEqual(model.restoreIssues.map(\.message), ["App - Missing: window not found"])
        XCTAssertEqual(model.statusMessage, "Restored 0 windows, 1 issue")
    }

    func testRestoreRequestsPermissionWhenAccessibilityIsNotTrusted() throws {
        let store = FakeWorkspaceStore()
        let workspace = Workspace(id: UUID(), name: "Coding", createdAt: Date(), updatedAt: Date(), windows: [])
        store.workspaces = [workspace]
        let permission = FakeWorkspacePermissionChecker(isTrusted: false)
        let model = WorkspacePanelModel(
            store: store,
            service: WorkspaceWindowService(
                snapshotProvider: FakeWorkspaceSnapshots(windows: []),
                restorer: FakeWorkspaceRestore()
            ),
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        try model.restore(workspace)

        XCTAssertEqual(permission.requestCount, 1)
        XCTAssertEqual(model.statusMessage, "Accessibility permission is required")
    }
}

private func workspaceWindow(_ title: String) -> WorkspaceWindow {
    WorkspaceWindow(
        bundleIdentifier: "com.example.app",
        appName: "App",
        windowTitle: title,
        frame: CGRect(x: 0, y: 0, width: 500, height: 400),
        screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
    )
}

private final class FakeWorkspaceStore: WorkspaceStoring {
    var workspaces: [Workspace] = []
    private(set) var savedWorkspaces: [Workspace] = []

    func load() throws -> [Workspace] {
        workspaces
    }

    func save(_ workspace: Workspace) throws {
        savedWorkspaces.append(workspace)
        workspaces = workspaces.filter { $0.id != workspace.id } + [workspace]
    }

    func delete(id: UUID) throws {
        workspaces.removeAll { $0.id == id }
    }
}

private struct FakeWorkspaceSnapshots: WindowSnapshotProviding {
    let windows: [WorkspaceWindow]

    func currentWindowSnapshots() throws -> [WorkspaceWindow] {
        windows
    }
}

private final class FakeWorkspaceRestore: WorkspaceRestoring {
    let report: WorkspaceRestoreReport

    init(report: WorkspaceRestoreReport = WorkspaceRestoreReport(restoredWindows: [], issues: [])) {
        self.report = report
    }

    func restore(_ workspace: Workspace) throws -> WorkspaceRestoreReport {
        report
    }
}

private final class FakeWorkspacePermissionChecker: WindowManagementPermissionChecking {
    var isTrusted: Bool
    private(set) var requestCount = 0

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func requestPermission() {
        requestCount += 1
    }
}
