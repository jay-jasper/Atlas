import XCTest
import UniformTypeIdentifiers
@testable import Atlas

@MainActor
final class ScreenshotDragOutputTests: XCTestCase {
    private var rootDirectory: URL!
    private var store: ScreenshotDragOutputStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotDragOutputTests-\(UUID().uuidString)", isDirectory: true)
        store = ScreenshotDragOutputStore(rootDirectory: rootDirectory)
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        store = nil
        rootDirectory = nil
        try super.tearDownWithError()
    }

    func testFilenameUsesTimestampAndIdentifier() {
        let filename = ScreenshotDragOutputStore.filename(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            date: Date(timeIntervalSince1970: 1_704_067_200)
        )

        XCTAssertEqual(filename, "Atlas Drag Screenshot 2024-01-01 00.00.00 11111111.png")
    }

    func testMakeDragItemWritesPngFile() throws {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        let item = try store.makeDragItem(
            pngData: Data([0x89, 0x50, 0x4E, 0x47]),
            id: id,
            date: date
        )

        XCTAssertEqual(item.filename, "Atlas Drag Screenshot 2024-01-01 00.00.00 AAAAAAAA.png")
        XCTAssertEqual(item.url.lastPathComponent, item.filename)
        XCTAssertEqual(try Data(contentsOf: item.url), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testMakeItemProviderRegistersFileURLAndPNGType() throws {
        let pngData = Data([1, 2, 3])
        let provider = try store.makeItemProvider(
            pngData: pngData,
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            date: Date(timeIntervalSince1970: 1_704_067_200)
        )

        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier))

        let expectation = expectation(description: "Load PNG data representation")
        provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, pngData)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testCleanupRemovesOnlyOldDragFiles() throws {
        let oldItem = try store.makeDragItem(
            pngData: Data([1]),
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            date: Date(timeIntervalSince1970: 10)
        )
        let freshItem = try store.makeDragItem(
            pngData: Data([2]),
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            date: Date(timeIntervalSince1970: 20)
        )
        let unrelatedURL = rootDirectory.appendingPathComponent("manual.txt")
        try Data([3]).write(to: unrelatedURL)
        let unrelatedPNGURL = rootDirectory.appendingPathComponent("other.png")
        try Data([4]).write(to: unrelatedPNGURL)
        let pngDirectoryURL = rootDirectory.appendingPathComponent("Atlas Drag Screenshot old.png", isDirectory: true)
        try FileManager.default.createDirectory(at: pngDirectoryURL, withIntermediateDirectories: true)

        let oldAttributes: [FileAttributeKey: Any] = [
            .modificationDate: Date(timeIntervalSince1970: 10),
        ]
        let freshAttributes: [FileAttributeKey: Any] = [
            .modificationDate: Date(timeIntervalSince1970: 20),
        ]
        try FileManager.default.setAttributes(oldAttributes, ofItemAtPath: oldItem.url.path)
        try FileManager.default.setAttributes(freshAttributes, ofItemAtPath: freshItem.url.path)
        try FileManager.default.setAttributes(oldAttributes, ofItemAtPath: unrelatedPNGURL.path)
        try FileManager.default.setAttributes(oldAttributes, ofItemAtPath: pngDirectoryURL.path)

        try store.cleanupFiles(olderThan: Date(timeIntervalSince1970: 15))

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldItem.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshItem.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedPNGURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pngDirectoryURL.path))
    }

    func testCleanupCutoffForDefaultRetention() {
        let now = Date(timeIntervalSince1970: 86_400 * 3)
        let cutoff = ScreenshotDragOutputStore.cleanupCutoff(now: now)

        XCTAssertEqual(cutoff, Date(timeIntervalSince1970: 86_400 * 2))
    }
}
