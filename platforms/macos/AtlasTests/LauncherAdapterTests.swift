import XCTest
@testable import Atlas

private struct StubProvider: CommandProviding {
    let commands: [PaletteCommand]
    func results(for query: String) -> [PaletteCommand] { commands }
}

private func makeCommand(
    title: String,
    subtitle: String? = nil,
    category: String,
    action: PaletteAction = .execute({})
) -> PaletteCommand {
    PaletteCommand(
        id: UUID(),
        title: title,
        subtitle: subtitle,
        icon: .sfSymbol("bolt"),
        keywords: [],
        action: action,
        category: category
    )
}

final class LauncherAdapterTests: XCTestCase {
    func testExecuteCommandMapsToPrimaryRunAction() {
        var executed = false
        let command = makeCommand(title: "Do It", category: "Tools", action: .execute({ executed = true }))
        let adapter = CommandProviderAdapter(provider: StubProvider(commands: [command]), sourceID: "stub")

        let items = adapter.items(for: "")
        XCTAssertEqual(items.count, 1)
        let primary = try! XCTUnwrap(items[0].primaryAction)
        XCTAssertEqual(primary.id, "run")

        guard case .dismiss = primary.perform() else {
            return XCTFail("expected dismiss outcome")
        }
        XCTAssertTrue(executed)
    }

    func testPushCommandMapsToLegacyPage() {
        let command = makeCommand(title: "Ports", category: "Atlas", action: .push(.portLookup))
        let adapter = CommandProviderAdapter(provider: StubProvider(commands: [command]), sourceID: "stub")

        let primary = try! XCTUnwrap(adapter.items(for: "")[0].primaryAction)
        guard case .push(let page) = primary.perform(),
              case .legacy(let destination) = page else {
            return XCTFail("expected legacy push page")
        }
        XCTAssertEqual(destination, .portLookup)
    }

    func testCalculatorMarkedAsAnswer() {
        let command = makeCommand(title: "2+2", subtitle: "4", category: "Calculator")
        let adapter = CommandProviderAdapter(provider: StubProvider(commands: [command]), sourceID: "stub")

        let item = adapter.items(for: "2+2")[0]
        XCTAssertTrue(item.isAnswer)
        XCTAssertTrue(item.actions.contains { $0.id == "copy-answer" })
    }

    func testFileCommandGetsDetailAndActions() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("launcher-adapter-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let command = makeCommand(title: "note.txt", subtitle: url.path, category: "Files")
        let adapter = CommandProviderAdapter(provider: StubProvider(commands: [command]), sourceID: "stub")

        let item = adapter.items(for: "note")[0]
        XCTAssertNotNil(item.detail)
        XCTAssertTrue(item.actions.contains { $0.id == "reveal" })
        XCTAssertTrue(item.actions.contains { $0.id == "copy-path" })
    }

    func testEmojiRootItemPushesGridPage() {
        let source = EmojiGridSource(copy: { _ in })
        let items = source.items(for: "emo")
        XCTAssertEqual(items.count, 1)

        guard case .push(let page) = items[0].primaryAction!.perform(),
              case .grid(let title, let columns, let gridItems) = page else {
            return XCTFail("expected grid page push")
        }
        XCTAssertEqual(title, "Emoji")
        XCTAssertEqual(columns, 8)
        XCTAssertEqual(gridItems().count, EmojiProvider.catalog.count)
    }

    func testEmojiGridCopyAction() {
        var copied: String?
        let source = EmojiGridSource(copy: { copied = $0 })
        guard case .push(let page) = source.items(for: "")[0].primaryAction!.perform(),
              case .grid(_, _, let gridItems) = page else {
            return XCTFail("expected grid page")
        }
        let first = gridItems()[0]
        _ = first.primaryAction!.perform()
        XCTAssertEqual(copied, EmojiProvider.catalog[0].glyph)
    }

    func testClipboardItemGetsPreviewDetail() {
        let command = makeCommand(title: "copied text sample", category: "Clipboard")
        let adapter = CommandProviderAdapter(provider: StubProvider(commands: [command]), sourceID: "stub")
        let item = adapter.items(for: "")[0]
        XCTAssertEqual(item.detail?.previewText, "copied text sample")
    }

    func testIDMatchesUsageStoreKey() {
        let command = makeCommand(title: "Do It", category: "Tools")
        let adapter = CommandProviderAdapter(provider: StubProvider(commands: [command]), sourceID: "stub")

        XCTAssertEqual(adapter.items(for: "")[0].id, CommandUsageStore.commandKey(for: command))
        XCTAssertEqual(adapter.items(for: "")[0].id, "Tools|Do It")
    }
}
