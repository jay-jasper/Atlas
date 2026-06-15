import CoreGraphics
import Foundation
import XCTest
@testable import Atlas

private final class FakeWindowCaptureProvider: WindowCaptureProviding {
    var windows: [CapturableWindow] = [
        CapturableWindow(id: 42, title: "Spec", ownerName: "Atlas", bounds: CGRect(x: 1, y: 2, width: 300, height: 200))
    ]
    var capturedWindowID: CGWindowID?
    var captureResult = Data([1, 2, 3])
    var captureError: Error?

    func listWindows() throws -> [CapturableWindow] {
        windows
    }

    func captureWindow(id: CGWindowID) throws -> Data {
        capturedWindowID = id
        if let captureError {
            throw captureError
        }
        return captureResult
    }
}

@MainActor
final class WindowCaptureServiceTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.windowCaptureProvider = CoreGraphicsWindowCaptureProvider()
        super.tearDown()
    }

    func testBridgeListsCapturableWindowsFromProvider() throws {
        let provider = FakeWindowCaptureProvider()
        AtlasBridge.windowCaptureProvider = provider

        let windows = try AtlasBridge.listCapturableWindows()

        XCTAssertEqual(windows, provider.windows)
    }

    func testBridgeCapturesWindowFromProvider() throws {
        let provider = FakeWindowCaptureProvider()
        AtlasBridge.windowCaptureProvider = provider

        let data = try AtlasBridge.captureWindow(id: 42)

        XCTAssertEqual(provider.capturedWindowID, 42)
        XCTAssertEqual(data, Data([1, 2, 3]))
    }

    func testLoggingProviderRecordsWindowCaptureAttempt() throws {
        let provider = FakeWindowCaptureProvider()
        let logger = FakeWindowCapturePrivacyPulseAccessLogger()
        let loggingProvider = LoggingWindowCaptureProvider(
            wrapped: provider,
            accessLogger: logger
        )

        let data = try loggingProvider.captureWindow(id: 42)

        XCTAssertEqual(data, Data([1, 2, 3]))
        XCTAssertEqual(logger.events.map(\.title), ["Window Capture"])
        XCTAssertEqual(logger.events.first?.category, .screenRecording)
    }

    func testCaptureErrorMessageIsLocalized() {
        let error = WindowCaptureError.captureFailed("denied")

        XCTAssertEqual(error.localizedDescription, "denied")
    }

    func testCapturableWindowIncludesLayerZeroWindow() {
        let window = CoreGraphicsWindowCaptureProvider.capturableWindow(from: windowInfo(layer: 0))

        XCTAssertEqual(
            window,
            CapturableWindow(id: 42, title: "Spec", ownerName: "Atlas", bounds: CGRect(x: 1, y: 2, width: 300, height: 200))
        )
    }

    func testCapturableWindowExcludesNonApplicationLayers() {
        XCTAssertNil(CoreGraphicsWindowCaptureProvider.capturableWindow(from: windowInfo(layer: 20)))
        XCTAssertNil(CoreGraphicsWindowCaptureProvider.capturableWindow(from: windowInfo(layer: 24)))
        XCTAssertNil(CoreGraphicsWindowCaptureProvider.capturableWindow(from: windowInfo(layer: 25)))
    }

    private func windowInfo(layer: Int) -> [String: Any] {
        [
            kCGWindowNumber as String: UInt32(42),
            kCGWindowLayer as String: layer,
            kCGWindowName as String: "Spec",
            kCGWindowOwnerName as String: "Atlas",
            kCGWindowBounds as String: [
                "X": 1,
                "Y": 2,
                "Width": 300,
                "Height": 200,
            ],
        ]
    }
}

private final class FakeWindowCapturePrivacyPulseAccessLogger: PrivacyPulseAccessLogging {
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
