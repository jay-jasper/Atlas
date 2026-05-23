import XCTest
@testable import Atlas

final class ClipboardHistoryProviderTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 100)

    func testCapturesCurrentClipboardTextIntoStore() {
        let reader = FakeClipboardReader(text: "hello")
        let store = InMemoryClipboardHistoryStore()
        let logger = FakePrivacyPulseAccessLogger()
        let provider = ClipboardHistoryProvider(
            reader: reader,
            store: store,
            isEnabled: { true },
            dateProvider: { self.now },
            accessLogger: logger
        )

        provider.captureCurrentClipboard()

        XCTAssertEqual(store.items().map(\.textValue), ["hello"])
        XCTAssertEqual(logger.events.map(\.title), ["Clipboard Read"])
    }

    func testCapturesImageMetadataWhenNoTextExists() {
        let metadata = ClipboardImageMetadata(typeIdentifier: "public.png", pixelWidth: 320, pixelHeight: 240, byteCount: 1024)
        let reader = FakeClipboardReader(text: nil, imageMetadata: metadata)
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { true }, dateProvider: { self.now })

        provider.captureCurrentClipboard()

        XCTAssertEqual(store.items().map(\.content), [.image(metadata)])
    }

    func testDisabledFeatureDoesNotReadClipboardOrReturnResults() {
        let reader = FakeClipboardReader(text: "secret")
        let store = InMemoryClipboardHistoryStore()
        let logger = FakePrivacyPulseAccessLogger()
        let provider = ClipboardHistoryProvider(
            reader: reader,
            store: store,
            isEnabled: { false },
            accessLogger: logger
        )

        provider.captureCurrentClipboard()
        let results = provider.results(for: "clip")

        XCTAssertEqual(reader.stringReadCount, 0)
        XCTAssertTrue(logger.events.isEmpty)
        XCTAssertTrue(store.items().isEmpty)
        XCTAssertTrue(results.isEmpty)
    }

    func testBlankQueryReturnsNoResults() {
        let reader = FakeClipboardReader(text: "hello")
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { true })

        provider.captureCurrentClipboard()

        XCTAssertTrue(provider.results(for: "").isEmpty)
    }

    func testClipboardQueryReturnsRecentTextResults() {
        let reader = FakeClipboardReader(text: "hello")
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { true })

        provider.captureCurrentClipboard()
        let results = provider.results(for: "clip")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "hello")
        XCTAssertEqual(results.first?.category, "Clipboard")
        XCTAssertEqual(results.first?.icon, .sfSymbol("doc.on.clipboard"))
    }

    func testQueryMatchesImageMetadata() {
        let metadata = ClipboardImageMetadata(typeIdentifier: "public.tiff", pixelWidth: 100, pixelHeight: 200, byteCount: nil)
        let reader = FakeClipboardReader(text: nil, imageMetadata: metadata)
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { true })

        provider.captureCurrentClipboard()
        let results = provider.results(for: "tiff")

        XCTAssertEqual(results.first?.title, "Image 100 x 200")
        XCTAssertEqual(results.first?.subtitle, "Image metadata only")
    }

    func testExecutingTextResultCopiesTextBackToClipboard() {
        let reader = FakeClipboardReader(text: "first")
        let store = InMemoryClipboardHistoryStore()
        let logger = FakePrivacyPulseAccessLogger()
        let provider = ClipboardHistoryProvider(
            reader: reader,
            store: store,
            isEnabled: { true },
            accessLogger: logger
        )

        provider.captureCurrentClipboard()
        reader.bumpChangeCount(text: "second", imageMetadata: nil)
        provider.captureCurrentClipboard()

        let result = provider.results(for: "first").first
        if case .execute(let execute)? = result?.action {
            execute()
        } else {
            XCTFail("expected executable clipboard result")
        }

        XCTAssertEqual(reader.writtenText, "first")
        XCTAssertEqual(logger.events.map(\.title), ["Clipboard Read", "Clipboard Read", "Clipboard Write"])
    }

    func testCaptureNotifiesPanelReloadCallback() {
        let reader = FakeClipboardReader(text: "visible without restart")
        let store = InMemoryClipboardHistoryStore()
        var panelItems: [ClipboardHistoryItem] = []
        let provider = ClipboardHistoryProvider(
            reader: reader,
            store: store,
            isEnabled: { true },
            onHistoryChanged: {
                panelItems = store.items()
            }
        )

        provider.captureCurrentClipboard()

        XCTAssertEqual(panelItems.map(\.textValue), ["visible without restart"])
    }
}

private final class FakePrivacyPulseAccessLogger: PrivacyPulseAccessLogging {
    struct Event: Equatable {
        let category: PrivacyPulseCategory
        let title: String
        let detail: String
    }

    private(set) var events: [Event] = []

    func record(category: PrivacyPulseCategory, title: String, detail: String) {
        events.append(Event(category: category, title: title, detail: detail))
    }
}

private final class FakeClipboardReader: ClipboardReading {
    private(set) var changeCount: Int
    private var currentText: String?
    private var currentImageMetadata: ClipboardImageMetadata?
    private(set) var writtenText: String?
    private(set) var stringReadCount = 0

    init(text: String?, imageMetadata: ClipboardImageMetadata? = nil, changeCount: Int = 1) {
        self.currentText = text
        self.currentImageMetadata = imageMetadata
        self.changeCount = changeCount
    }

    func string() -> String? {
        stringReadCount += 1
        return currentText
    }

    func imageMetadata() -> ClipboardImageMetadata? {
        currentImageMetadata
    }

    func setString(_ text: String) {
        writtenText = text
        currentText = text
        currentImageMetadata = nil
        changeCount += 1
    }

    func bumpChangeCount(text: String?, imageMetadata: ClipboardImageMetadata?) {
        currentText = text
        currentImageMetadata = imageMetadata
        changeCount += 1
    }
}

private final class InMemoryClipboardHistoryStore: ClipboardHistoryStoring {
    private var storedItems: [ClipboardHistoryItem] = []

    func items() -> [ClipboardHistoryItem] {
        storedItems
    }

    func search(_ query: String) -> [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return storedItems }
        return storedItems.filter { $0.searchableText.localizedCaseInsensitiveContains(trimmed) }
    }

    func addText(_ text: String, capturedAt: Date) {
        storedItems.insert(ClipboardHistoryItem(id: UUID(), content: .text(text), capturedAt: capturedAt), at: 0)
    }

    func addImageMetadata(_ metadata: ClipboardImageMetadata, capturedAt: Date) {
        storedItems.insert(ClipboardHistoryItem(id: UUID(), content: .image(metadata), capturedAt: capturedAt), at: 0)
    }

    func delete(id: UUID) {
        storedItems.removeAll { $0.id == id }
    }

    func clear() {
        storedItems = []
    }
}
