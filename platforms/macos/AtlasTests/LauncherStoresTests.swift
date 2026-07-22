import XCTest
@testable import Atlas

@MainActor
final class LauncherStoresTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "LauncherStoresTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: Favorites

    func testTogglePinsAndUnpins() {
        let store = FavoritesStore(defaults: defaults)
        store.toggle("Tools|Alpha")
        XCTAssertTrue(store.isPinned("Tools|Alpha"))
        store.toggle("Tools|Alpha")
        XCTAssertFalse(store.isPinned("Tools|Alpha"))
    }

    func testFavoritesPersistOrder() {
        let store = FavoritesStore(defaults: defaults)
        store.toggle("a")
        store.toggle("b")
        store.toggle("c")
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        let reloaded = FavoritesStore(defaults: defaults)
        XCTAssertEqual(reloaded.pinnedKeys, ["c", "a", "b"])
    }

    // MARK: Aliases

    func testAliasSetAndRemove() {
        let store = AliasStore(defaults: defaults)
        store.setAlias("GH", for: "Tools|GitHub")
        XCTAssertEqual(store.alias(for: "Tools|GitHub"), "gh")
        store.setAlias(nil, for: "Tools|GitHub")
        XCTAssertNil(store.alias(for: "Tools|GitHub"))
        store.setAlias("  ", for: "Tools|GitHub")
        XCTAssertNil(store.alias(for: "Tools|GitHub"))
    }

    func testAliasPrefixMatch() {
        let store = AliasStore(defaults: defaults)
        store.setAlias("ghub", for: "Tools|GitHub")
        XCTAssertEqual(store.commandKey(matching: "ghub"), "Tools|GitHub")
        XCTAssertEqual(store.commandKey(matching: "gh"), "Tools|GitHub")
        XCTAssertNil(store.commandKey(matching: "xyz"))
        XCTAssertNil(store.commandKey(matching: ""))
    }

    func testAliasUniqueLastWriteWins() {
        let store = AliasStore(defaults: defaults)
        store.setAlias("gh", for: "Tools|GitHub")
        store.setAlias("gh", for: "Tools|GitLab")
        XCTAssertNil(store.alias(for: "Tools|GitHub"))
        XCTAssertEqual(store.alias(for: "Tools|GitLab"), "gh")
    }

    func testAliasPersists() {
        AliasStore(defaults: defaults).setAlias("gh", for: "Tools|GitHub")
        XCTAssertEqual(AliasStore(defaults: defaults).alias(for: "Tools|GitHub"), "gh")
    }

    // MARK: Quicklinks

    func testResolvedURLEncodesQuery() {
        let quicklink = Quicklink(name: "GitHub", template: "https://github.com/search?q={query}")
        XCTAssertEqual(
            quicklink.resolvedURL(argument: "swift charts")?.absoluteString,
            "https://github.com/search?q=swift%20charts"
        )
    }

    func testResolvedURLNilWithoutRequiredArgument() {
        let quicklink = Quicklink(name: "GitHub", template: "https://github.com/search?q={query}")
        XCTAssertNil(quicklink.resolvedURL(argument: nil))
        XCTAssertNil(quicklink.resolvedURL(argument: ""))

        let fixed = Quicklink(name: "Docs", template: "https://docs.example.com")
        XCTAssertEqual(fixed.resolvedURL(argument: nil)?.absoluteString, "https://docs.example.com")
    }

    func testQuicklinkCRUDPersists() {
        let store = QuicklinkStore(defaults: defaults)
        var quicklink = Quicklink(name: "GitHub", template: "https://github.com/search?q={query}")
        store.add(quicklink)

        quicklink.name = "GH Search"
        store.update(quicklink)

        var reloaded = QuicklinkStore(defaults: defaults)
        XCTAssertEqual(reloaded.quicklinks.map(\.name), ["GH Search"])

        reloaded.remove(id: quicklink.id)
        XCTAssertTrue(QuicklinkStore(defaults: defaults).quicklinks.isEmpty)
    }

    func testQuicklinkItemHeadPlusArgument() {
        let store = QuicklinkStore(defaults: defaults)
        store.add(Quicklink(name: "gh", template: "https://github.com/search?q={query}"))

        let items = store.makeItems(query: "gh swift charts")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].subtitle, "Open with \"swift charts\"")
        XCTAssertTrue(items[0].acceptsArgument)
    }

    // MARK: Fallbacks

    func testFallbackDefaultsSeeded() {
        let store = FallbackStore(defaults: defaults)
        XCTAssertEqual(store.commands.map(\.id), ["google", "duckduckgo", "translate"])
    }

    func testFallbackReorderPersists() {
        let store = FallbackStore(defaults: defaults)
        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(FallbackStore(defaults: defaults).commands.first?.id, "duckduckgo")
    }

    func testFallbackDisabledExcluded() {
        let store = FallbackStore(defaults: defaults)
        store.setEnabled(false, id: "google")
        let items = store.makeItems(query: "zzz")
        XCTAssertFalse(items.contains { $0.title == "Search Google" })
        XCTAssertTrue(items.contains { $0.title == "Search DuckDuckGo" })
    }

    func testFallbackEmptyQueryProducesNoItems() {
        XCTAssertTrue(FallbackStore(defaults: defaults).makeItems(query: "  ").isEmpty)
    }

    // MARK: Command hotkeys

    func testHotkeyStorePersists() {
        let store = CommandHotkeyStore(defaults: defaults)
        store.set(HotkeyConfig(keyCode: 11, modifiers: 1_048_840), for: "Tools|GitHub")

        let reloaded = CommandHotkeyStore(defaults: defaults)
        XCTAssertEqual(reloaded.hotkeys["Tools|GitHub"]?.keyCode, 11)
        XCTAssertEqual(reloaded.hotkeys["Tools|GitHub"]?.modifiers, 1_048_840)

        reloaded.set(nil, for: "Tools|GitHub")
        XCTAssertTrue(CommandHotkeyStore(defaults: defaults).hotkeys.isEmpty)
    }
}
