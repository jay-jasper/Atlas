import XCTest
@testable import Atlas

@MainActor
final class WorkspaceWindowServiceTests: XCTestCase {
    func testCaptureCreatesNamedWorkspaceFromInjectedSnapshots() throws {
        let service = WorkspaceWindowService(
            snapshotProvider: FakeSnapshotProvider(windows: [window(title: "Editor")]),
            restorer: FakeWorkspaceRestorer()
        )

        let workspace = try service.captureWorkspace(named: "Coding", now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(workspace.name, "Coding")
        XCTAssertEqual(workspace.createdAt, Date(timeIntervalSince1970: 50))
        XCTAssertEqual(workspace.updatedAt, Date(timeIntervalSince1970: 50))
        XCTAssertEqual(workspace.windows.map(\.windowTitle), ["Editor"])
    }

    func testRestoreReturnsReportFromInjectedRestorer() throws {
        let target = window(title: "Editor")
        let expected = WorkspaceRestoreReport(
            restoredWindows: [target],
            issues: [WorkspaceRestoreIssue(window: window(title: "Missing"), reason: .windowNotFound)]
        )
        let restorer = FakeWorkspaceRestorer(report: expected)
        let service = WorkspaceWindowService(
            snapshotProvider: FakeSnapshotProvider(windows: []),
            restorer: restorer
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Coding",
            createdAt: Date(),
            updatedAt: Date(),
            windows: [target]
        )

        let report = try service.restore(workspace)

        XCTAssertEqual(report, expected)
        XCTAssertEqual(restorer.restoredWorkspaces, [workspace])
    }
}

private func window(title: String) -> WorkspaceWindow {
    WorkspaceWindow(
        bundleIdentifier: "com.example.editor",
        appName: "Editor",
        windowTitle: title,
        frame: CGRect(x: 10, y: 20, width: 800, height: 600),
        screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
    )
}

private struct FakeSnapshotProvider: WindowSnapshotProviding {
    let windows: [WorkspaceWindow]

    func currentWindowSnapshots() throws -> [WorkspaceWindow] {
        windows
    }
}

private final class FakeWorkspaceRestorer: WorkspaceRestoring {
    let report: WorkspaceRestoreReport
    private(set) var restoredWorkspaces: [Workspace] = []

    init(report: WorkspaceRestoreReport = WorkspaceRestoreReport(restoredWindows: [], issues: [])) {
        self.report = report
    }

    func restore(_ workspace: Workspace) throws -> WorkspaceRestoreReport {
        restoredWorkspaces.append(workspace)
        return report
    }
}
