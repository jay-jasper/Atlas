import XCTest
@testable import Atlas

final class RaycastFeatureTests: XCTestCase {
    // MARK: Placeholder parser

    func testPlaceholdersResolve() {
        let fixed = Date(timeIntervalSince1970: 1_753_100_000) // 2026-07-21 UTC 附近
        let context = SnippetPlaceholderParser.Context(
            clipboard: { "剪贴板内容" },
            now: { fixed },
            uuid: { "UUID-1" },
            argumentValues: ["参数值"]
        )
        let resolved = SnippetPlaceholderParser.resolve(
            "A {clipboard} B {uuid} C {argument:输入} D",
            context: context
        )
        XCTAssertEqual(resolved.text, "A 剪贴板内容 B UUID-1 C 参数值 D")
        XCTAssertNil(resolved.cursorOffsetFromEnd)
        XCTAssertEqual(resolved.argumentPrompts, ["输入"])
    }

    func testDatePlaceholderCustomFormat() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let now = Date()
        let context = SnippetPlaceholderParser.Context(
            clipboard: { "" }, now: { now }, uuid: { "" }, argumentValues: []
        )
        let resolved = SnippetPlaceholderParser.resolve("{date:yyyy/MM/dd}", context: context)
        XCTAssertEqual(resolved.text, formatter.string(from: now))
    }

    func testCursorPlaceholderOffset() {
        let context = SnippetPlaceholderParser.Context(
            clipboard: { "" }, now: { Date() }, uuid: { "" }, argumentValues: []
        )
        let resolved = SnippetPlaceholderParser.resolve("abc{cursor}xyz", context: context)
        XCTAssertEqual(resolved.text, "abcxyz")
        XCTAssertEqual(resolved.cursorOffsetFromEnd, 3)
    }

    func testUnknownPlaceholderKeptLiteral() {
        let context = SnippetPlaceholderParser.Context(
            clipboard: { "" }, now: { Date() }, uuid: { "" }, argumentValues: []
        )
        let resolved = SnippetPlaceholderParser.resolve("x {nope} y", context: context)
        XCTAssertEqual(resolved.text, "x {nope} y")
    }

    // MARK: Expansion engine

    func testKeywordHitAtWordBoundary() {
        var engine = SnippetExpansionEngine(entries: [
            .init(id: "1", keyword: ";mail", body: "hello@example.com"),
        ])
        var match: SnippetExpansionEngine.Match?
        for ch in "say ;mail" {
            match = engine.ingest(ch) ?? match
        }
        XCTAssertEqual(match?.snippetID, "1")
        XCTAssertTrue(engine.buffer.isEmpty, "buffer clears after hit")
    }

    func testMidWordKeywordDoesNotFire() {
        var engine = SnippetExpansionEngine(entries: [
            .init(id: "1", keyword: "sig", body: "signature"),
        ])
        var match: SnippetExpansionEngine.Match?
        for ch in "design" { // 含 sig 但在词中
            match = engine.ingest(ch) ?? match
        }
        XCTAssertNil(match)
    }

    func testBackspaceEditsBuffer() {
        var engine = SnippetExpansionEngine(entries: [
            .init(id: "1", keyword: ";x", body: "b"),
        ])
        _ = engine.ingest(";")
        _ = engine.ingest("y")
        _ = engine.ingest("\u{8}") // 删掉 y
        let match = engine.ingest("x")
        XCTAssertNotNil(match)
    }

    func testResetClearsBuffer() {
        var engine = SnippetExpansionEngine(entries: [
            .init(id: "1", keyword: ";x", body: "b"),
        ])
        _ = engine.ingest(";")
        engine.reset()
        XCTAssertNil(engine.ingest("x"))
    }

    // MARK: Meeting links

    func testMeetingLinkDetection() {
        XCTAssertEqual(
            MeetingLinkDetector.firstLink(in: "join https://us02web.zoom.us/j/123456?pwd=abc now")?.host,
            "us02web.zoom.us"
        )
        XCTAssertEqual(
            MeetingLinkDetector.firstLink(in: "https://meet.google.com/abc-defg-hij")?.host,
            "meet.google.com"
        )
        XCTAssertEqual(
            MeetingLinkDetector.firstLink(in: "https://meeting.tencent.com/dm/AbCd123")?.host,
            "meeting.tencent.com"
        )
        XCTAssertNil(MeetingLinkDetector.firstLink(in: "no links here"))
        XCTAssertNil(MeetingLinkDetector.firstLink(in: nil))
    }

    // MARK: System commands

    func testSystemCatalogShapes() {
        let commands = SystemCommandCatalog.commands
        XCTAssertEqual(commands.count, 13)
        XCTAssertEqual(Set(commands.map(\.id)).count, commands.count, "ids unique")
        let dangerous = commands.filter(\.needsConfirm).map(\.id)
        XCTAssertEqual(
            Set(dangerous),
            ["sys-logout", "sys-restart", "sys-shutdown", "sys-empty-trash"]
        )
    }

    func testSystemCommandShellRouting() {
        final class SpyProcess: SystemCommandProcess {
            var isRunning = false
            func terminate() {}
        }
        struct SpyRunner: SystemCommandRunning {
            let onRun: (String, [String]) -> Void
            func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
                onRun(executable, arguments)
                return SystemCommandResult(terminationStatus: 0, standardOutput: "", standardError: "")
            }
            func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
                SpyProcess()
            }
        }
        var ranShell: (String, [String])?
        var ranScript: String?
        let lock = SystemCommandCatalog.commands.first { $0.id == "sys-lock" }!
        SystemCommandCatalog.run(
            lock,
            runner: SpyRunner(onRun: { ranShell = ($0, $1) }),
            appleScriptRunner: { ranScript = $0 }
        )
        XCTAssertEqual(ranShell?.0, "/usr/bin/pmset")
        XCTAssertNil(ranScript)

        let sleep = SystemCommandCatalog.commands.first { $0.id == "sys-sleep" }!
        SystemCommandCatalog.run(
            sleep,
            runner: SpyRunner(onRun: { _, _ in }),
            appleScriptRunner: { ranScript = $0 }
        )
        XCTAssertNotNil(ranScript)
    }

    // MARK: Translate

    func testTranslateAutoTargetSwitch() {
        MainActor.assumeIsolated {
            let service = TranslateService.shared
            service.targetLanguage = "zh-Hans"
            service.secondaryLanguage = "en"
            XCTAssertEqual(service.effectiveTarget(for: "hello world"), "zh-Hans")
            XCTAssertEqual(service.effectiveTarget(for: "你好世界"), "en", "中文输入自动换英文目标")
        }
    }

    func testTranslatePromptShape() {
        let prompt = TranslateService.prompt(text: "hi", target: "zh-Hans")
        XCTAssertTrue(prompt.contains("简体中文"))
        XCTAssertTrue(prompt.hasSuffix("hi"))
    }

    // MARK: Focus service formatting

    func testFocusTimeFormat() {
        XCTAssertEqual(FocusService.format(seconds: 0), "00:00")
        XCTAssertEqual(FocusService.format(seconds: 65), "01:05")
        XCTAssertEqual(FocusService.format(seconds: 25 * 60), "25:00")
    }

    // MARK: Calendar provider mapping

    func testCalendarProviderRowsAndMeetingAction() {
        var opened: URL?
        let meeting = URL(string: "https://meet.google.com/abc-defg-hij")!
        let provider = CalendarEventsProvider(
            eventsLookup: { _ in
                [
                    (title: "站会", start: Date(timeIntervalSince1970: 1_753_200_000), meeting: meeting, eventID: "e1"),
                    (title: "无会议日程", start: Date(), meeting: nil, eventID: "e2"),
                ]
            },
            open: { opened = $0 }
        )
        let rows = provider.results(for: "")
        XCTAssertEqual(rows.count, 2)
        if case .execute(let action) = rows[0].action {
            action()
        }
        XCTAssertEqual(opened, meeting)
    }

    // MARK: Transfer kinds

    @MainActor
    func testTransferDefaultsRoundtrip() {
        let key = "snippets.expansion.keywords"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set(["snip1": ";kw"], forKey: key)
        let kind = TransferKinds.all.first { $0.id == "snippets" }!
        guard let payload = TransferKinds.gather(kind) else {
            return XCTFail("gather failed")
        }
        UserDefaults.standard.removeObject(forKey: key)
        TransferKinds.apply(payload)
        XCTAssertEqual(
            UserDefaults.standard.dictionary(forKey: key) as? [String: String],
            ["snip1": ";kw"]
        )
    }
}
