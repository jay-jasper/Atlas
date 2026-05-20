import XCTest
@testable import Atlas

final class ScreenshotLibraryTests: XCTestCase {
    private var rootDirectory: URL!
    private var store: ScreenshotLibraryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotLibraryTests-\(UUID().uuidString)", isDirectory: true)
        store = ScreenshotLibraryStore(rootDirectory: rootDirectory)
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        store = nil
        rootDirectory = nil
        try super.tearDownWithError()
    }

    func testLoadItemsReturnsEmptyArrayBeforeIndexExists() throws {
        XCTAssertEqual(try store.loadItems(), [])
    }

    func testAddScreenshotWritesPngAndIndexEntry() throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let capturedAt = Date(timeIntervalSince1970: 1_704_067_200)

        let item = try store.addScreenshot(
            pngData: pngData,
            pixelWidth: 320,
            pixelHeight: 200,
            source: "Window",
            capturedAt: capturedAt
        )

        XCTAssertEqual(item.pixelWidth, 320)
        XCTAssertEqual(item.pixelHeight, 200)
        XCTAssertEqual(item.dimensionsText, "320 x 200")
        XCTAssertEqual(item.source, "Window")
        XCTAssertEqual(item.recognizedText, "")
        XCTAssertEqual(item.translatedText, "")
        XCTAssertEqual(try Data(contentsOf: store.pngURL(for: item)), pngData)
        XCTAssertEqual(try store.pngData(for: item), pngData)
        XCTAssertEqual(try store.loadItems(), [item])
    }

    func testIndexPersistsCapturedAtAsISO8601Text() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_704_067_200)

        _ = try store.addScreenshot(
            pngData: Data([1]),
            pixelWidth: 320,
            pixelHeight: 200,
            source: "Window",
            capturedAt: capturedAt
        )

        let indexURL = rootDirectory.appendingPathComponent("index.json", isDirectory: false)
        let indexJSON = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(indexJSON.contains(#""capturedAt" : "2024-01-01T00:00:00Z""#))
        XCTAssertFalse(indexJSON.contains(#""capturedAt" : 1704067200"#))
    }

    func testLoadItemsSortsNewestFirst() throws {
        let older = try store.addScreenshot(
            pngData: Data([1]),
            pixelWidth: 10,
            pixelHeight: 10,
            source: "Desktop",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = try store.addScreenshot(
            pngData: Data([2]),
            pixelWidth: 20,
            pixelHeight: 20,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(try store.loadItems().map(\.id), [newer.id, older.id])
    }

    func testLoadItemsSortsSameCaptureDateByUUIDAscending() throws {
        let capturedAt = Date(timeIntervalSince1970: 10)
        let first = try store.addScreenshot(
            pngData: Data([1]),
            pixelWidth: 10,
            pixelHeight: 10,
            source: "Desktop",
            capturedAt: capturedAt
        )
        let second = try store.addScreenshot(
            pngData: Data([2]),
            pixelWidth: 20,
            pixelHeight: 20,
            source: "Area",
            capturedAt: capturedAt
        )

        XCTAssertEqual(
            try store.loadItems().map(\.id),
            [first.id, second.id].sorted { $0.uuidString < $1.uuidString }
        )
    }

    func testUpdateRecognizedAndTranslatedText() throws {
        let item = try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            pixelWidth: 120,
            pixelHeight: 80,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 10)
        )

        try store.updateText(
            id: item.id,
            recognizedText: "Hello Atlas",
            translatedText: "你好 Atlas"
        )

        let updated = try XCTUnwrap(store.loadItems().first)
        XCTAssertEqual(updated.recognizedText, "Hello Atlas")
        XCTAssertEqual(updated.translatedText, "你好 Atlas")
    }

    func testUpdateTextPreservesNilFieldsAndNoOpsMissingID() throws {
        let item = try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            pixelWidth: 120,
            pixelHeight: 80,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 10)
        )

        try store.updateText(id: item.id, recognizedText: "Alpha", translatedText: "Beta")
        try store.updateText(id: item.id, recognizedText: nil, translatedText: "Gamma")
        try store.updateText(id: UUID(), recognizedText: "Ignored", translatedText: "Ignored")

        let updated = try XCTUnwrap(store.loadItems().first)
        XCTAssertEqual(updated.recognizedText, "Alpha")
        XCTAssertEqual(updated.translatedText, "Gamma")
    }

    func testSearchMatchesSourceRecognizedAndTranslatedTextCaseInsensitively() throws {
        _ = try store.addScreenshot(
            pngData: Data([1]),
            pixelWidth: 100,
            pixelHeight: 100,
            source: "Desktop",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let invoice = try store.addScreenshot(
            pngData: Data([2]),
            pixelWidth: 200,
            pixelHeight: 100,
            source: "Window",
            capturedAt: Date(timeIntervalSince1970: 20)
        )
        try store.updateText(
            id: invoice.id,
            recognizedText: "Invoice total due",
            translatedText: "发票总额"
        )

        XCTAssertEqual(try store.search(query: "invoice").map(\.id), [invoice.id])
        XCTAssertEqual(try store.search(query: "发票").map(\.id), [invoice.id])
        XCTAssertEqual(try store.search(query: "window").map(\.id), [invoice.id])
        XCTAssertEqual(try store.search(query: "missing"), [])
    }

    func testBlankSearchReturnsAllItemsNewestFirst() throws {
        let first = try store.addScreenshot(
            pngData: Data([1]),
            pixelWidth: 10,
            pixelHeight: 10,
            source: "Desktop",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let second = try store.addScreenshot(
            pngData: Data([2]),
            pixelWidth: 20,
            pixelHeight: 20,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(try store.search(query: "   ").map(\.id), [second.id, first.id])
    }

    func testDeleteRemovesIndexEntryAndPngFile() throws {
        let item = try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            pixelWidth: 120,
            pixelHeight: 80,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let pngURL = store.pngURL(for: item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pngURL.path))

        try store.delete(id: item.id)
        try store.delete(id: UUID())

        XCTAssertEqual(try store.loadItems(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: pngURL.path))
    }

    func testDeleteSavesIndexBeforeRemovingPngFile() throws {
        let fileManager = RemoveFailingFileManager()
        store = ScreenshotLibraryStore(rootDirectory: rootDirectory, fileManager: fileManager)
        let item = try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            pixelWidth: 120,
            pixelHeight: 80,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertThrowsError(try store.delete(id: item.id)) { error in
            XCTAssertEqual(error as? RemoveFailingFileManager.RemoveError, .failed)
        }
        XCTAssertEqual(try store.loadItems(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.pngURL(for: item).path))
    }

    func testPngDataThrowsMissingImageWhenFileIsMissing() throws {
        let item = try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            pixelWidth: 120,
            pixelHeight: 80,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        try FileManager.default.removeItem(at: store.pngURL(for: item))

        XCTAssertThrowsError(try store.pngData(for: item)) { error in
            XCTAssertEqual(error as? ScreenshotLibraryError, .missingImage(item.id))
            XCTAssertEqual(error.localizedDescription, "Screenshot image is missing from the local library")
        }
    }
}

private final class RemoveFailingFileManager: FileManager {
    enum RemoveError: Error, Equatable {
        case failed
    }

    override func removeItem(at URL: URL) throws {
        throw RemoveError.failed
    }
}
