import AppKit
import XCTest
@testable import Atlas

@MainActor
final class AtlasBridgeCaptureTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.captureService = .live
        AtlasBridge.windowCaptureProvider = CoreGraphicsWindowCaptureProvider()
        super.tearDown()
    }

    func testBridgeRegionUsesCaptureService() throws {
        AtlasBridge.captureService = AtlasCaptureService(
            captureFullScreen: { Data([9]) },
            captureRegion: { x, y, width, height in
                XCTAssertEqual(x, 1)
                XCTAssertEqual(y, 2)
                XCTAssertEqual(width, 3)
                XCTAssertEqual(height, 4)
                return Data([1, 2, 3])
            }
        )
        let data = try AtlasBridge.captureRegion(x: 1, y: 2, width: 3, height: 4)
        XCTAssertEqual(data, Data([1, 2, 3]))
    }

    func testBridgeFullScreenUsesCaptureService() throws {
        AtlasBridge.captureService = AtlasCaptureService(
            captureFullScreen: { Data([7, 8]) },
            captureRegion: { _, _, _, _ in Data() }
        )
        let data = try AtlasBridge.captureFullScreen()
        XCTAssertEqual(data, Data([7, 8]))
    }

    func testBridgeListsWindowsFromWindowProvider() throws {
        let provider = BridgeWindowProvider()
        AtlasBridge.windowCaptureProvider = provider

        let windows = try AtlasBridge.listCapturableWindows()

        XCTAssertEqual(windows, provider.windows)
    }

    func testBridgeCapturesWindowFromWindowProvider() throws {
        let provider = BridgeWindowProvider()
        AtlasBridge.windowCaptureProvider = provider

        let data = try AtlasBridge.captureWindow(id: 7)

        XCTAssertEqual(provider.capturedID, 7)
        XCTAssertEqual(data, Data([4, 5, 6]))
    }
}

private final class BridgeWindowProvider: WindowCaptureProviding {
    var windows = [
        CapturableWindow(id: 7, title: "Window", ownerName: "Atlas", bounds: CGRect(x: 0, y: 0, width: 100, height: 80))
    ]
    var capturedID: CGWindowID?

    func listWindows() throws -> [CapturableWindow] {
        windows
    }

    func captureWindow(id: CGWindowID) throws -> Data {
        capturedID = id
        return Data([4, 5, 6])
    }
}
