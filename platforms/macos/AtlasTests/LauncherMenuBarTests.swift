import XCTest
@testable import Atlas

private struct StubReader: MenuBarReading {
    let entries: [MenuBarEntry]
    func frontmostAppMenuItems() -> [MenuBarEntry] { entries }
}

@MainActor
final class LauncherMenuBarTests: XCTestCase {
    private let entries = [
        MenuBarEntry(path: ["File", "Export…"], element: nil),
        MenuBarEntry(path: ["Edit", "Copy"], element: nil),
        MenuBarEntry(path: ["View", "Zoom", "Zoom In"], element: nil),
    ]

    func testReturnsPermissionItemWhenUntrusted() {
        let source = MenuBarItemSource(reader: StubReader(entries: entries), isTrusted: { false })
        let items = source.items(for: "menu copy")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "MenuBar|grant-access")
    }

    func testFiltersMenuEntriesByQuery() {
        let source = MenuBarItemSource(reader: StubReader(entries: entries), isTrusted: { true })
        let items = source.items(for: "menu copy")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Copy")
    }

    func testEntryTitleJoinsPath() {
        let source = MenuBarItemSource(reader: StubReader(entries: entries), isTrusted: { true })
        let items = source.items(for: "sm export")
        XCTAssertEqual(items[0].subtitle, "File › Export…")
    }

    func testNoPrefixNoItems() {
        let source = MenuBarItemSource(reader: StubReader(entries: entries), isTrusted: { true })
        XCTAssertTrue(source.items(for: "copy").isEmpty)
        XCTAssertTrue(source.items(for: "").isEmpty)
    }

    func testEmptyTermListsAll() {
        let source = MenuBarItemSource(reader: StubReader(entries: entries), isTrusted: { true })
        XCTAssertEqual(source.items(for: "menu ").count, 3)
    }
}
