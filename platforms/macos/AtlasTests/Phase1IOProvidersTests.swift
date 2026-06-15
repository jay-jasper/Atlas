import XCTest
@testable import Atlas

private final class StubRunner: SystemCommandRunning {
    var output: String
    init(output: String) { self.output = output }
    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        SystemCommandResult(terminationStatus: 0, standardOutput: output, standardError: "")
    }
    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
        SpyShellProcess()
    }
}

private final class SpyShellProcess: SystemCommandProcess {
    var isRunning = false
    func terminate() {}
}

@MainActor
final class FileSearchProviderTests: XCTestCase {
    func testParsesMdfindOutput() {
        var opened: [String] = []
        let runner = StubRunner(output: "/Users/x/a.txt\n/Users/x/b.txt\n")
        let provider = FileSearchProvider(commandRunner: runner, open: { opened.append($0) })
        let results = provider.results(for: "f report")
        XCTAssertEqual(results.map(\.title), ["a.txt", "b.txt"])
        if case .execute(let run)? = results.first?.action { run() }
        XCTAssertEqual(opened, ["/Users/x/a.txt"])
    }

    func testShortTermReturnsEmpty() {
        XCTAssertTrue(FileSearchProvider(commandRunner: StubRunner(output: "")).results(for: "f a").isEmpty)
    }

    func testNonKeywordReturnsEmpty() {
        XCTAssertTrue(FileSearchProvider(commandRunner: StubRunner(output: "")).results(for: "hello").isEmpty)
    }
}

@MainActor
final class BookmarkProviderTests: XCTestCase {
    private let chromeJSON = """
    {"roots":{"bookmark_bar":{"type":"folder","children":[
      {"type":"url","name":"GitHub","url":"https://github.com"},
      {"type":"folder","name":"Work","children":[
        {"type":"url","name":"Linear","url":"https://linear.app"}
      ]}
    ]}}}
    """

    func testParseChromium() {
        let data = Data(chromeJSON.utf8)
        let bookmarks = BookmarkProvider.parseChromium(data, source: "Chrome")
        XCTAssertEqual(bookmarks.count, 2)
        XCTAssertTrue(bookmarks.contains(Bookmark(title: "GitHub", url: "https://github.com", source: "Chrome")))
        XCTAssertTrue(bookmarks.contains(Bookmark(title: "Linear", url: "https://linear.app", source: "Chrome")))
    }

    func testSearchAndOpen() {
        var opened: [String] = []
        let provider = BookmarkProvider(
            loader: { [Bookmark(title: "GitHub", url: "https://github.com", source: "Chrome")] },
            open: { opened.append($0) }
        )
        let results = provider.results(for: "git")
        XCTAssertEqual(results.first?.title, "GitHub")
        if case .execute(let run)? = results.first?.action { run() }
        XCTAssertEqual(opened, ["https://github.com"])
    }

    func testShortQueryReturnsEmpty() {
        let provider = BookmarkProvider(loader: { [Bookmark(title: "GitHub", url: "x", source: "Chrome")] })
        XCTAssertTrue(provider.results(for: "gi").isEmpty)
    }
}

@MainActor
final class ShellScriptProviderTests: XCTestCase {
    func testListsAndRunsMatchingScript() {
        var ran: [String] = []
        let store = InMemoryShellStore(scripts: [
            ShellScript(name: "deploy", body: "echo deploy"),
            ShellScript(name: "backup", body: "echo backup"),
        ])
        let provider = ShellScriptProvider(store: store, execute: { ran.append($0.name) })
        let results = provider.results(for: "run dep")
        XCTAssertEqual(results.map(\.title), ["Run deploy"])
        if case .execute(let run)? = results.first?.action { run() }
        XCTAssertEqual(ran, ["deploy"])
    }

    func testRunWithNoTermListsAll() {
        let store = InMemoryShellStore(scripts: [ShellScript(name: "a", body: "x"), ShellScript(name: "b", body: "y")])
        XCTAssertEqual(ShellScriptProvider(store: store, execute: { _ in }).results(for: "run").count, 2)
    }

    func testNonKeywordReturnsEmpty() {
        let store = InMemoryShellStore(scripts: [ShellScript(name: "a", body: "x")])
        XCTAssertTrue(ShellScriptProvider(store: store, execute: { _ in }).results(for: "running").isEmpty)
    }
}

@MainActor
final class ShellScriptStoreTests: XCTestCase {
    private func tempStore() -> ShellScriptStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-shell-\(UUID().uuidString).json")
        return ShellScriptStore(fileURL: url)
    }

    func testUpsertAndLoad() throws {
        let store = tempStore()
        try store.upsert(ShellScript(name: "deploy", body: "echo hi"))
        XCTAssertEqual(store.scripts().map(\.name), ["deploy"])
    }

    func testRejectsDuplicateNames() {
        let store = tempStore()
        XCTAssertThrowsError(try store.save([
            ShellScript(name: "a", body: "x"),
            ShellScript(name: "A", body: "y"),
        ]))
    }

    func testRejectsInvalidScript() {
        XCTAssertThrowsError(try tempStore().save([ShellScript(name: "", body: "")]))
    }
}

private final class InMemoryShellStore: ShellScriptStoring {
    private var store: [ShellScript]
    init(scripts: [ShellScript]) { store = scripts }
    func scripts() -> [ShellScript] { store }
    func save(_ scripts: [ShellScript]) throws { store = scripts }
    func upsert(_ script: ShellScript) throws { store.append(script) }
    func delete(id: UUID) throws { store.removeAll { $0.id == id } }
}
