import AppKit
import XCTest
@testable import Atlas

@MainActor
final class ScreenshotOutputTests: XCTestCase {
    func testPngFilenameUsesTimestamp() {
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        let filename = ScreenshotOutput.filename(for: date)
        XCTAssertEqual(filename, "Atlas Screenshot 2024-01-01 00.00.00.png")
    }

    func testWritePngData() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = try ScreenshotOutput.writePNG(data, to: directory, date: Date(timeIntervalSince1970: 1_704_067_200))

        XCTAssertEqual(url.lastPathComponent, "Atlas Screenshot 2024-01-01 00.00.00.png")
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testCopyPngLogsClipboardWriteThroughInjectedBoundary() {
        let pasteboard = FakeScreenshotPasteboard()
        let logger = FakeScreenshotPrivacyPulseAccessLogger()

        ScreenshotOutput.copyPNGToClipboard(
            Data([1, 2, 3]),
            pasteboard: pasteboard,
            accessLogger: logger
        )

        XCTAssertEqual(pasteboard.clearCount, 1)
        XCTAssertEqual(pasteboard.data, Data([1, 2, 3]))
        XCTAssertEqual(pasteboard.type, .png)
        XCTAssertEqual(logger.events.map(\.title), ["Clipboard Write"])
        XCTAssertEqual(logger.events.first?.category, .clipboard)
    }
}

private final class FakeScreenshotPasteboard: ScreenshotPasteboardWriting {
    private(set) var clearCount = 0
    private(set) var data: Data?
    private(set) var type: NSPasteboard.PasteboardType?

    func clearContents() -> Int {
        clearCount += 1
        data = nil
        type = nil
        return clearCount
    }

    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        self.data = data
        self.type = dataType
        return true
    }
}

private final class FakeScreenshotPrivacyPulseAccessLogger: PrivacyPulseAccessLogging {
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
