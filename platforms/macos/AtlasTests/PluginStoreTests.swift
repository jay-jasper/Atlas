import XCTest
@testable import Atlas

@MainActor
final class PluginStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PluginStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStoreAliasesFindPluginStoreCommand() {
        let store = MockPluginStore(defaults: defaults)
        let source = PluginStoreSource(store: store)

        for query in ["plugin", "store", "插件", "商店"] {
            let sections = LauncherSectionBuilder.build(
                query: query,
                sources: [source],
                favorites: [],
                records: [:]
            )
            XCTAssertEqual(
                sections.flatMap(\.items).map(\.id),
                ["PluginStore|Open"],
                "Expected \(query) to find the plugin store"
            )
        }
    }

    func testInstallPersistsAcrossStoreInstances() throws {
        let store = MockPluginStore(defaults: defaults)
        let listing = try XCTUnwrap(store.catalog.first)

        store.install(listing)

        XCTAssertTrue(store.isInstalled(listing))
        let restored = MockPluginStore(defaults: defaults)
        XCTAssertTrue(restored.isInstalled(listing))
    }

    func testQueryAndCategoryFilterCatalog() {
        let store = MockPluginStore(defaults: defaults)

        XCTAssertEqual(store.listings(matching: "翻译").map(\.id), ["google-translate"])

        store.selectedCategory = .developerTools
        XCTAssertEqual(store.listings(matching: "").map(\.id), ["visual-studio-code"])
        XCTAssertTrue(store.listings(matching: "spotify").isEmpty)
    }

    func testCategoryCatalogMatchesInitialStoreTaxonomy() {
        XCTAssertEqual(
            PluginStoreCategory.allCases.map(\.rawValue),
            [
                "AI Extensions",
                "Applications",
                "Communication",
                "Data",
                "Documentation",
                "Design Tools",
                "Developer Tools",
                "Finance",
                "Fun",
                "Media",
                "News",
                "Productivity",
                "Security",
                "System",
                "Web",
                "Other",
            ]
        )
        XCTAssertEqual(PluginStoreCategory.allCases.count, 16)
        XCTAssertTrue(PluginStoreCategory.allCases.allSatisfy { !$0.title.isEmpty })
    }

    func testInstalledFilterOnlyShowsInstalledPlugins() throws {
        let store = MockPluginStore(defaults: defaults)
        let listing = try XCTUnwrap(store.catalog.last)
        store.install(listing)
        store.installedOnly = true

        XCTAssertEqual(store.listings(matching: "").map(\.id), [listing.id])
    }

    func testPrimaryActionInstallsListingWithoutDismissingStore() throws {
        let store = MockPluginStore(defaults: defaults)
        let listing = try XCTUnwrap(store.catalog.first)
        let item = try XCTUnwrap(store.launcherItems(matching: listing.name).first)
        let action = try XCTUnwrap(item.primaryAction)

        guard case .stay = action.perform() else {
            return XCTFail("Install should keep the store page open")
        }
        XCTAssertTrue(store.isInstalled(listing))
    }
}
