import XCTest
@testable import Atlas

final class SnippetStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SnippetStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultSnippetsAreReturnedWhenStorageIsEmpty() {
        let store = SnippetStore(defaults: defaults)

        let snippets = store.snippets()

        XCTAssertEqual(snippets.map(\.title), [
            "Email Greeting",
            "Meeting Notes",
            "Bug Report",
            "Thank You",
        ])
    }

    func testSnippetHasStableIdentityFromID() {
        let snippet = Snippet(
            id: "thanks",
            title: "Thank You",
            body: "Thanks!",
            keywords: ["thanks"]
        )

        XCTAssertEqual(snippet.id, "thanks")
    }

    func testSaveAndLoadCustomSnippetsRoundTrips() {
        let store = SnippetStore(defaults: defaults)
        let snippets = [
            Snippet(
                id: "custom",
                title: "Custom Reply",
                body: "I will take a look.",
                keywords: ["reply", "custom"]
            )
        ]

        store.save(snippets)

        XCTAssertEqual(store.snippets(), snippets)
    }

    func testSaveFiltersBlankTitleOrBodySnippets() {
        let store = SnippetStore(defaults: defaults)
        let snippets = [
            Snippet(id: "good", title: "Good", body: "Useful text", keywords: []),
            Snippet(id: "blank-title", title: "  ", body: "Useful text", keywords: []),
            Snippet(id: "blank-body", title: "No Body", body: "\n ", keywords: []),
        ]

        store.save(snippets)

        XCTAssertEqual(store.snippets(), [
            Snippet(id: "good", title: "Good", body: "Useful text", keywords: []),
        ])
    }

    func testClearRestoresDefaults() {
        let store = SnippetStore(defaults: defaults)
        store.save([
            Snippet(id: "custom", title: "Custom", body: "Body", keywords: []),
        ])

        store.clear()

        XCTAssertEqual(store.snippets().map(\.title), [
            "Email Greeting",
            "Meeting Notes",
            "Bug Report",
            "Thank You",
        ])
    }
}
