import XCTest
@testable import Atlas

@MainActor
final class ScreenshotCaptureModeTests: XCTestCase {
    func testModesHaveStableOrder() {
        XCTAssertEqual(ScreenshotCaptureMode.allCases, [.desktop, .window, .area])
    }

    func testModeLabels() {
        XCTAssertEqual(ScreenshotCaptureMode.desktop.title, "Desktop")
        XCTAssertEqual(ScreenshotCaptureMode.window.title, "Window")
        XCTAssertEqual(ScreenshotCaptureMode.area.title, "Area")
    }

    func testModeSymbols() {
        XCTAssertEqual(ScreenshotCaptureMode.desktop.systemImage, "display")
        XCTAssertEqual(ScreenshotCaptureMode.window.systemImage, "macwindow")
        XCTAssertEqual(ScreenshotCaptureMode.area.systemImage, "selection.pin.in.out")
    }
}
