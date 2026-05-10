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

    func testCaptureErrorMessageIsLocalized() {
        let error = WindowCaptureError.captureFailed("denied")

        XCTAssertEqual(error.localizedDescription, "denied")
    }
}
