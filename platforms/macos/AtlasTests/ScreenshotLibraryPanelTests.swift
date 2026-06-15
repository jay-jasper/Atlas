import XCTest
@testable import Atlas

@MainActor
final class ScreenshotLibraryPanelTests: XCTestCase {
    func testEmptyStateShowsNoScreenshotsSavedYet() {
        let state = ScreenshotLibraryPanelState(items: [], query: "")

        XCTAssertEqual(state.visibleItems, [])
        XCTAssertEqual(state.countText, "0 screenshots")
        XCTAssertEqual(state.emptyText, "No screenshots saved yet")
    }

    func testRecognizedTextFilteringTrimsQueryAndUpdatesCount() {
        let matching = item(id: 1, recognizedText: "Invoice Total")
        let nonmatching = item(id: 2, recognizedText: "Receipt")

        let state = ScreenshotLibraryPanelState(items: [matching, nonmatching], query: " total ")

        XCTAssertEqual(state.visibleItems, [matching])
        XCTAssertEqual(state.countText, "1 of 2 screenshots")
        XCTAssertEqual(state.emptyText, "No screenshots match the search")
    }

    func testTranslatedAndSourceFilteringIsCaseInsensitive() {
        let sourceMatch = item(id: 1, source: "Desktop")
        let translatedMatch = item(id: 2, translatedText: "Bonjour Atlas")
        let nonmatching = item(id: 3, source: "Window", translatedText: "Hola")

        let sourceState = ScreenshotLibraryPanelState(
            items: [sourceMatch, translatedMatch, nonmatching],
            query: "desktop"
        )
        let translatedState = ScreenshotLibraryPanelState(
            items: [sourceMatch, translatedMatch, nonmatching],
            query: "BONJOUR"
        )

        XCTAssertEqual(sourceState.visibleItems, [sourceMatch])
        XCTAssertEqual(sourceState.countText, "1 of 3 screenshots")
        XCTAssertEqual(translatedState.visibleItems, [translatedMatch])
        XCTAssertEqual(translatedState.countText, "1 of 3 screenshots")
    }

    func testInputOrderIsPreserved() {
        let first = item(id: 1, source: "Area", recognizedText: "Atlas")
        let second = item(id: 2, source: "Window", translatedText: "Atlas")
        let third = item(id: 3, source: "Desktop", recognizedText: "Atlas")

        let state = ScreenshotLibraryPanelState(items: [first, second, third], query: "atlas")

        XCTAssertEqual(state.visibleItems, [first, second, third])
        XCTAssertEqual(state.countText, "3 screenshots")
    }

    private func item(
        id: UInt8,
        source: String = "Window",
        recognizedText: String = "",
        translatedText: String = ""
    ) -> ScreenshotLibraryItem {
        ScreenshotLibraryItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02X", id))")!,
            filename: "\(id).png",
            capturedAt: Date(timeIntervalSince1970: TimeInterval(id)),
            pixelWidth: 100,
            pixelHeight: 50,
            source: source,
            recognizedText: recognizedText,
            translatedText: translatedText
        )
    }
}
