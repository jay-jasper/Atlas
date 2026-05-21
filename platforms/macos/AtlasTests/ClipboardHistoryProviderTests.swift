import XCTest
@testable import Atlas

final class ClipboardHistoryProviderTests: XCTestCase {
    func testCapturesCurrentClipboardText() {
        let reader = FakeClipboardReader(text: "hello")
        let provider = ClipboardHistoryProvider(reader: reader)

        provider.captureCurrentClipboard()

        XCTAssertEqual(provider.items.map(\.text), ["hello"])
    }

    func testIgnoresBlankClipboardText() {
        let reader = FakeClipboardReader(text: " \n ")
        let provider = ClipboardHistoryProvider(reader: reader)

        provider.captureCurrentClipboard()

        XCTAssertTrue(provider.items.isEmpty)
    }

    func testDoesNotDuplicateMostRecentClipboardText() {
        let reader = FakeClipboardReader(text: "same")
        let provider = ClipboardHistoryProvider(reader: reader)

        provider.captureCurrentClipboard()
        reader.bumpChangeCount(text: "same")
        provider.captureCurrentClipboard()

        XCTAssertEqual(provider.items.map(\.text), ["same"])
    }

    func testCapsHistory() {
        let reader = FakeClipboardReader(text: "one")
        let provider = ClipboardHistoryProvider(reader: reader, maxHistoryCount: 2)

        provider.captureCurrentClipboard()
        reader.bumpChangeCount(text: "two")
        provider.captureCurrentClipboard()
        reader.bumpChangeCount(text: "three")
        provider.captureCurrentClipboard()

        XCTAssertEqual(provider.items.map(\.text), ["three", "two"])
    }

    func testBlankQueryReturnsNoResults() {
        let reader = FakeClipboardReader(text: "hello")
        let provider = ClipboardHistoryProvider(reader: reader)

        provider.captureCurrentClipboard()

        XCTAssertTrue(provider.results(for: "").isEmpty)
    }

    func testClipboardQueryReturnsRecentResults() {
        let reader = FakeClipboardReader(text: "hello")
        let provider = ClipboardHistoryProvider(reader: reader)

        provider.captureCurrentClipboard()
        let results = provider.results(for: "clip")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "hello")
        XCTAssertEqual(results.first?.category, "Clipboard")
        XCTAssertEqual(results.first?.icon, .sfSymbol("doc.on.clipboard"))
    }

    func testQueryTextMatchesHistoryContent() {
        let reader = FakeClipboardReader(text: "invoice number 42")
        let provider = ClipboardHistoryProvider(reader: reader)

        provider.captureCurrentClipboard()
        let results = provider.results(for: "number")

        XCTAssertEqual(results.first?.title, "invoice number 42")
    }

    func testExecutingResultCopiesTextBackToClipboard() {
        let reader = FakeClipboardReader(text: "first")
        let provider = ClipboardHistoryProvider(reader: reader)

        provider.captureCurrentClipboard()
        reader.bumpChangeCount(text: "second")
        provider.captureCurrentClipboard()

        let result = provider.results(for: "first").first
        if case .execute(let execute)? = result?.action {
            execute()
        } else {
            XCTFail("expected executable clipboard result")
        }

        XCTAssertEqual(reader.writtenText, "first")
    }

    func testTitleUsesFirstLineAndCapsLength() {
        let longLine = String(repeating: "a", count: 90)
        let reader = FakeClipboardReader(text: "\(longLine)\nsecond")
        let provider = ClipboardHistoryProvider(reader: reader)

        provider.captureCurrentClipboard()
        let result = provider.results(for: "clip").first

        XCTAssertEqual(result?.title.count, 80)
        XCTAssertFalse(result?.title.contains("\n") ?? true)
    }
}

private final class FakeClipboardReader: ClipboardReading {
    private(set) var changeCount: Int
    private var currentText: String?
    private(set) var writtenText: String?

    init(text: String?, changeCount: Int = 1) {
        self.currentText = text
        self.changeCount = changeCount
    }

    func string() -> String? {
        currentText
    }

    func setString(_ text: String) {
        writtenText = text
        currentText = text
        changeCount += 1
    }

    func bumpChangeCount(text: String?) {
        currentText = text
        changeCount += 1
    }
}
