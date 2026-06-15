import AppKit
import XCTest
@testable import Atlas

@MainActor
final class ScreenshotGIFOutputTests: XCTestCase {
    func testWritesTemporaryGIFFileWithStableExtension() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GIFOutputTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = ScreenshotGIFOutputStore(rootDirectory: root)

        let item = try output.writeTemporaryGIF(
            Data([1, 2, 3]),
            date: Date(timeIntervalSince1970: 1_704_067_200)
        )

        XCTAssertTrue(item.url.lastPathComponent.hasSuffix(".gif"))
        XCTAssertEqual(try Data(contentsOf: item.url), Data([1, 2, 3]))
        XCTAssertEqual(item.filename, "Atlas-GIF-20240101-000000.gif")
    }

    func testPasteboardItemContainsFileURL() throws {
        let url = URL(fileURLWithPath: "/tmp/Atlas-GIF-test.gif")
        let item = ScreenshotGIFOutputItem(url: url, filename: "Atlas-GIF-test.gif")

        let pasteboardItem = ScreenshotGIFPasteboardWriter.pasteboardItem(for: item)

        XCTAssertEqual(pasteboardItem.string(forType: .fileURL), url.absoluteString)
    }
}
