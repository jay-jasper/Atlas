import XCTest
@testable import Atlas

@MainActor
final class TextExpansionEngineTests: XCTestCase {
    private let snippets = [
        TextSnippet(trigger: ":email", expansion: "me@example.com"),
        TextSnippet(trigger: ":sig", expansion: "Best,\nAlice"),
        TextSnippet(trigger: ":sign", expansion: "longer"),
    ]

    func testMatchesSuffixTrigger() {
        let match = TextExpansionEngine.match(buffer: "hello :email", snippets: snippets)
        XCTAssertEqual(match, .init(deleteCount: 6, insertText: "me@example.com"))
    }

    func testPrefersLongestTrigger() {
        let match = TextExpansionEngine.match(buffer: "type :sign", snippets: snippets)
        XCTAssertEqual(match?.insertText, "longer")
        XCTAssertEqual(match?.deleteCount, 5)
    }

    func testNoMatch() {
        XCTAssertNil(TextExpansionEngine.match(buffer: "nothing here", snippets: snippets))
    }

    func testPlaceholderExpansion() {
        let date = Date(timeIntervalSince1970: 0) // 1970-01-01 00:00 UTC
        let result = TextExpansionEngine.expandPlaceholders("d={date} t={time}", now: date)
        XCTAssertTrue(result.hasPrefix("d=19") || result.hasPrefix("d=1969")) // tz-dependent year prefix
        XCTAssertTrue(result.contains("t="))
    }
}

@MainActor
final class TextExpansionStoreTests: XCTestCase {
    private func tempStore() -> TextExpansionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-textexp-\(UUID().uuidString).json")
        return TextExpansionStore(fileURL: url)
    }

    func testUpsertAndLoad() throws {
        let store = tempStore()
        try store.upsert(TextSnippet(trigger: ":a", expansion: "alpha"))
        XCTAssertEqual(store.snippets().map(\.trigger), [":a"])
    }

    func testRejectsDuplicateTrigger() {
        let store = tempStore()
        XCTAssertThrowsError(try store.save([
            TextSnippet(trigger: ":x", expansion: "1"),
            TextSnippet(trigger: ":X", expansion: "2"),
        ]))
    }

    func testRejectsInvalid() {
        XCTAssertThrowsError(try tempStore().save([TextSnippet(trigger: "", expansion: "")]))
    }
}

private final class StubMonitor: TextExpansionMonitoring {
    var onResolveExpansion: ((String) -> TextExpansionEngine.Match?)?
    var startResult = true
    private(set) var stopped = false
    func start() -> Bool { startResult }
    func stop() { stopped = true }
}

@MainActor
final class TextExpansionServiceTests: XCTestCase {
    func testAddAndDelete() {
        let service = TextExpansionService(store: InMemoryTextExpansionStore(), monitor: StubMonitor())
        service.add(trigger: ":hi", expansion: "hello")
        XCTAssertEqual(service.snippets.count, 1)
        let id = service.snippets[0].id
        service.delete(id: id)
        XCTAssertTrue(service.snippets.isEmpty)
    }

    func testMonitorResolutionUsesSnippets() {
        let monitor = StubMonitor()
        let service = TextExpansionService(store: InMemoryTextExpansionStore(), monitor: monitor)
        service.add(trigger: ":hi", expansion: "hello")
        let match = monitor.onResolveExpansion?("say :hi")
        XCTAssertEqual(match?.insertText, "hello")
    }

    func testStartMonitoringFailureSetsStatus() {
        let monitor = StubMonitor()
        monitor.startResult = false
        let service = TextExpansionService(store: InMemoryTextExpansionStore(), monitor: monitor)
        service.startMonitoring()
        XCTAssertFalse(service.isMonitoring)
        XCTAssertFalse(service.statusMessage.isEmpty)
    }
}
