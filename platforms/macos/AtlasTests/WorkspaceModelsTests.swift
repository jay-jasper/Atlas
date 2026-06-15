import XCTest
@testable import Atlas

@MainActor
final class WorkspaceModelsTests: XCTestCase {
    func testWorkspaceRoundTripsThroughJSON() throws {
        let workspace = Workspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Writing",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            windows: [
                WorkspaceWindow(
                    bundleIdentifier: "com.apple.TextEdit",
                    appName: "TextEdit",
                    windowTitle: "Draft.txt",
                    frame: CGRect(x: 10, y: 20, width: 800, height: 600),
                    screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
                ),
            ]
        )

        let data = try JSONEncoder.workspaceEncoder.encode([workspace])
        let decoded = try JSONDecoder.workspaceDecoder.decode([Workspace].self, from: data)

        XCTAssertEqual(decoded, [workspace])
    }

    func testRestoreReportSeparatesRestoredAndMissingWindows() {
        let restored = WorkspaceWindow(
            bundleIdentifier: "com.apple.Terminal",
            appName: "Terminal",
            windowTitle: "atlas",
            frame: CGRect(x: 0, y: 0, width: 700, height: 500),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        let issue = WorkspaceRestoreIssue(
            window: restored,
            reason: .windowNotFound
        )

        let report = WorkspaceRestoreReport(restoredWindows: [restored], issues: [issue])

        XCTAssertEqual(report.restoredWindows, [restored])
        XCTAssertEqual(report.issues, [issue])
        XCTAssertEqual(issue.message, "Terminal - atlas: window not found")
    }
}
