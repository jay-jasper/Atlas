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
}
