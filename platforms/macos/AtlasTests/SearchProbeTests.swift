import XCTest
@testable import Atlas

@MainActor
final class SearchProbeTests: XCTestCase {
    func testAntiDoesNotMatchCaptureCommands() {
        let provider = AtlasCommandProvider(
            onCaptureDesktop: {}, onCaptureArea: {}, onCaptureWindow: {}, onOpenSettings: {}
        )
        let adapter = CommandProviderAdapter(provider: provider, sourceID: "atlas")
        let sections = LauncherSectionBuilder.build(
            query: "anti", sources: [adapter], favorites: [], records: [:]
        )
        XCTAssertTrue(sections.isEmpty, "got: \(sections.flatMap(\.items).map(\.title))")
    }

    func testFinderDoesNotMatchCaptureEvenWithUsageRecords() {
        // 用户实拍 bug:输入 finder 出现 Capture Area/Desktop。
        // frecency 权重不得把不匹配的高频命令顶回结果。
        let provider = AtlasCommandProvider(
            onCaptureDesktop: {}, onCaptureArea: {}, onCaptureWindow: {}, onOpenSettings: {}
        )
        let adapter = CommandProviderAdapter(provider: provider, sourceID: "atlas")
        let ids = adapter.items(for: "").map(\.id)
        let records = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, CommandUsageRecord(commandKey: $0, executionCount: 50, lastExecutedAt: Date()))
        })
        let sections = LauncherSectionBuilder.build(
            query: "finder", sources: [adapter], favorites: [], records: records
        )
        let titles = sections.flatMap(\.items).map(\.title)
        XCTAssertTrue(titles.isEmpty, "finder must not match capture commands, got: \(titles)")
        XCTAssertFalse(sections.contains { $0.id == .recents }, "recents must not render with query")
    }

    func testFileSearchNoPrefixNeeded() {
        final class StubProcess: SystemCommandProcess {
            var isRunning = false
            func terminate() {}
        }
        struct StubRunner: SystemCommandRunning {
            func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
                SystemCommandResult(
                    terminationStatus: 0,
                    standardOutput: "/Users/x/deep/notes-finder.txt\n/Users/x/finder-notes.md\n/Users/x/App.app\n",
                    standardError: ""
                )
            }
            func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
                StubProcess()
            }
        }
        let provider = FileSearchProvider(commandRunner: StubRunner(), open: { _ in })
        let results = provider.results(for: "finder")
        XCTAssertEqual(results.map(\.title), ["finder-notes.md", "notes-finder.txt"],
                       "prefix hit first, .app excluded, no 'f ' prefix required")
    }
}
