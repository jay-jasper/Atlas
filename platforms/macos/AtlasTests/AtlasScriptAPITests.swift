import XCTest
@testable import Atlas

@MainActor
final class AtlasScriptAPITests: XCTestCase {
    func testRegisterAndDispatch() {
        let api = AtlasScriptAPI()
        api.register("math.add") { args in
            let sum = args.compactMap(Int.init).reduce(0, +)
            return .ok(String(sum))
        }
        XCTAssertTrue(api.has("math.add"))
        XCTAssertEqual(api.dispatch("math.add", args: ["2", "3"]), .ok("5"))
    }

    func testUnknownCommandErrors() {
        let api = AtlasScriptAPI()
        XCTAssertEqual(api.dispatch("nope"), .error("unknown command 'nope'"))
    }

    func testCaseInsensitiveAndSortedListing() {
        let api = AtlasScriptAPI()
        api.register("B.run") { _ in .ok("") }
        api.register("a.run") { _ in .ok("") }
        XCTAssertEqual(api.available(), ["a.run", "b.run"])
        XCTAssertTrue(api.has("A.RUN"))
    }

    func testLineRunnerDispatchesEachLine() {
        let api = AtlasScriptAPI()
        var calls: [String] = []
        api.register("notify") { args in calls.append(args.joined(separator: " ")); return .ok("done") }
        let result = LineScriptRunner().run("-- comment\nnotify hello\nnotify world", api: api)
        XCTAssertEqual(calls, ["hello", "world"])
        XCTAssertEqual(result, .ok("done"))
    }

    func testLineRunnerStopsOnError() {
        let api = AtlasScriptAPI()
        var ran = 0
        api.register("ok.cmd") { _ in ran += 1; return .ok("") }
        let result = LineScriptRunner().run("ok.cmd\nbad.cmd\nok.cmd", api: api)
        if case .error = result {} else { XCTFail("expected error") }
        XCTAssertEqual(ran, 1) // stopped after the bad command
    }
}

@MainActor
final class ScriptingServiceTests: XCTestCase {
    func testBuiltinsRegistered() {
        let service = ScriptingService()
        XCTAssertTrue(service.availableCommands.contains("clipboard.set"))
        XCTAssertTrue(service.availableCommands.contains("open.url"))
        XCTAssertTrue(service.availableCommands.contains("notify"))
    }

    func testRunReportsOutput() {
        let service = ScriptingService()
        service.script = "notify scripted run"
        service.run()
        XCTAssertTrue(service.output.contains("notified"))
    }

    func testRunReportsErrorForUnknownCommand() {
        let service = ScriptingService()
        service.script = "does.not.exist"
        service.run()
        XCTAssertTrue(service.output.hasPrefix("✗"))
    }
}
