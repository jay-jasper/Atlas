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
