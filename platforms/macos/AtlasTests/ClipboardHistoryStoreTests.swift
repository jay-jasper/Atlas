import XCTest
@testable import Atlas

final class ClipboardHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ClipboardHistoryStoreTests"

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

    func testStartsEmpty() {
        let store = ClipboardHistoryStore(defaults: defaults)

        XCTAssertTrue(store.items().isEmpty)
    }

    func testAddTextPersistsNewestFirst() {
        let store = ClipboardHistoryStore(defaults: defaults)
        let first = Date(timeIntervalSince1970: 10)
        let second = Date(timeIntervalSince1970: 20)

        store.addText("alpha", capturedAt: first)
        store.addText("beta", capturedAt: second)

        let reloaded = ClipboardHistoryStore(defaults: defaults)
        XCTAssertEqual(reloaded.items().map(\.displayTitle), ["beta", "alpha"])
    }

    func testAddTextIgnoresBlankValues() {
        let store = ClipboardHistoryStore(defaults: defaults)

        store.addText(" \n ", capturedAt: Date(timeIntervalSince1970: 10))

        XCTAssertTrue(store.items().isEmpty)
    }

    func testAddTextMovesDuplicateToFront() {
        let store = ClipboardHistoryStore(defaults: defaults)

        store.addText("same", capturedAt: Date(timeIntervalSince1970: 10))
        store.addText("other", capturedAt: Date(timeIntervalSince1970: 20))
        store.addText("same", capturedAt: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(store.items().map(\.displayTitle), ["same", "other"])
        XCTAssertEqual(store.items().first?.capturedAt, Date(timeIntervalSince1970: 30))
    }

    func testAddImageMetadataPersistsWithoutImageBytes() {
        let store = ClipboardHistoryStore(defaults: defaults)
        let metadata = ClipboardImageMetadata(
            typeIdentifier: "public.png",
            pixelWidth: 640,
            pixelHeight: 480,
            byteCount: 2048
        )

        store.addImageMetadata(metadata, capturedAt: Date(timeIntervalSince1970: 40))

        XCTAssertEqual(store.items(), [
            ClipboardHistoryItem(
                id: store.items()[0].id,
                content: .image(metadata),
                capturedAt: Date(timeIntervalSince1970: 40)
            ),
        ])
        XCTAssertEqual(store.items().first?.displayTitle, "Image 640 x 480")
        XCTAssertEqual(store.items().first?.searchableText, "image public.png 640 x 480 2048 bytes")
    }

    func testSearchMatchesTextAndImageMetadata() {
        let store = ClipboardHistoryStore(defaults: defaults)
        store.addText("Invoice 42", capturedAt: Date(timeIntervalSince1970: 10))
        store.addImageMetadata(
            ClipboardImageMetadata(typeIdentifier: "public.tiff", pixelWidth: 100, pixelHeight: 200, byteCount: nil),
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(store.search("invoice").map(\.displayTitle), ["Invoice 42"])
        XCTAssertEqual(store.search("tiff").map(\.displayTitle), ["Image 100 x 200"])
    }

    func testDeleteRemovesMatchingItem() {
        let store = ClipboardHistoryStore(defaults: defaults)
        store.addText("keep", capturedAt: Date(timeIntervalSince1970: 10))
        store.addText("remove", capturedAt: Date(timeIntervalSince1970: 20))
        let removedID = store.items()[0].id

        store.delete(id: removedID)

        XCTAssertEqual(store.items().map(\.displayTitle), ["keep"])
    }

    func testClearRemovesAllItems() {
        let store = ClipboardHistoryStore(defaults: defaults)
        store.addText("one", capturedAt: Date(timeIntervalSince1970: 10))
        store.addText("two", capturedAt: Date(timeIntervalSince1970: 20))

        store.clear()

        XCTAssertTrue(store.items().isEmpty)
    }

    func testMaxRetentionIsApplied() {
        let store = ClipboardHistoryStore(defaults: defaults, maxHistoryCount: 2)

        store.addText("one", capturedAt: Date(timeIntervalSince1970: 10))
        store.addText("two", capturedAt: Date(timeIntervalSince1970: 20))
        store.addText("three", capturedAt: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(store.items().map(\.displayTitle), ["three", "two"])
    }
}
