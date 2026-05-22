import AppKit
import XCTest
@testable import Atlas

final class ScreenshotScrollingCaptureTests: XCTestCase {
    func testCapturesFramesScrollsBetweenFramesAndPersistsLibraryItem() throws {
        let frame = try png(width: 8, height: 4, color: .red)
        let storeRoot = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let libraryStore = ScreenshotLibraryStore(rootDirectory: storeRoot)
        let frameCapture = StubScrollingFrameCapture(frames: [frame, frame, frame])
        let scroller = StubScrollEventSender()

        let result = try ScreenshotScrollingCaptureService(
            permissions: StubScrollingPermissions(screenRecordingAllowed: true, accessibilityAllowed: true),
            frameCapture: frameCapture,
            scrollSender: scroller,
            stitcher: VerticalScreenshotImageStitcher(),
            libraryStore: libraryStore
        ).capture(
            request: ScrollingCaptureRequest(
                window: CapturableWindow(id: 42, title: "Document", ownerName: "Preview", bounds: .zero),
                maxFrames: 3,
                scrollDelta: -8,
                overlapPixels: 0
            )
        )

        XCTAssertEqual(frameCapture.windowIDs, [42, 42, 42])
        XCTAssertEqual(scroller.windowIDs, [42, 42])
        XCTAssertEqual(scroller.deltas, [-8, -8])
        XCTAssertEqual(result.framesCaptured, 3)
        XCTAssertEqual(result.libraryItem.source, "Scrolling Window: Preview - Document")
        let storedItem = try XCTUnwrap(libraryStore.loadItems().first)
        XCTAssertEqual(storedItem.id, result.libraryItem.id)
        XCTAssertEqual(storedItem.source, result.libraryItem.source)
        XCTAssertEqual(storedItem.pixelWidth, result.libraryItem.pixelWidth)
        XCTAssertEqual(storedItem.pixelHeight, result.libraryItem.pixelHeight)
        XCTAssertEqual(try libraryStore.pngData(for: result.libraryItem), result.pngData)
    }

    func testStopsAtMaximumFrames() throws {
        let frame = try png(width: 8, height: 4, color: .blue)
        let frameCapture = StubScrollingFrameCapture(frames: [frame, frame, frame, frame])
        let service = ScreenshotScrollingCaptureService(
            permissions: StubScrollingPermissions(screenRecordingAllowed: true, accessibilityAllowed: true),
            frameCapture: frameCapture,
            scrollSender: StubScrollEventSender(),
            stitcher: VerticalScreenshotImageStitcher(),
            libraryStore: ScreenshotLibraryStore(rootDirectory: temporaryRoot())
        )

        let result = try service.capture(
            request: ScrollingCaptureRequest(
                window: CapturableWindow(id: 7, title: "Feed", ownerName: "Safari", bounds: .zero),
                maxFrames: 2,
                scrollDelta: -5,
                overlapPixels: 0
            )
        )

        XCTAssertEqual(result.framesCaptured, 2)
        XCTAssertEqual(frameCapture.windowIDs, [7, 7])
    }

    func testReportsMissingScreenRecordingPermissionBeforeCapture() {
        let frameCapture = StubScrollingFrameCapture(frames: [])
        let scroller = StubScrollEventSender()
        let service = ScreenshotScrollingCaptureService(
            permissions: StubScrollingPermissions(screenRecordingAllowed: false, accessibilityAllowed: true),
            frameCapture: frameCapture,
            scrollSender: scroller,
            stitcher: VerticalScreenshotImageStitcher(),
            libraryStore: ScreenshotLibraryStore(rootDirectory: temporaryRoot())
        )

        XCTAssertThrowsError(try service.capture(request: request())) { error in
            XCTAssertEqual(error as? ScrollingCaptureError, .screenRecordingPermissionMissing)
        }
        XCTAssertEqual(frameCapture.windowIDs, [])
        XCTAssertEqual(scroller.windowIDs, [])
    }

    func testReportsMissingAccessibilityPermissionBeforeCapture() {
        let frameCapture = StubScrollingFrameCapture(frames: [])
        let scroller = StubScrollEventSender()
        let service = ScreenshotScrollingCaptureService(
            permissions: StubScrollingPermissions(screenRecordingAllowed: true, accessibilityAllowed: false),
            frameCapture: frameCapture,
            scrollSender: scroller,
            stitcher: VerticalScreenshotImageStitcher(),
            libraryStore: ScreenshotLibraryStore(rootDirectory: temporaryRoot())
        )

        XCTAssertThrowsError(try service.capture(request: request())) { error in
            XCTAssertEqual(error as? ScrollingCaptureError, .accessibilityPermissionMissing)
        }
        XCTAssertEqual(frameCapture.windowIDs, [])
        XCTAssertEqual(scroller.windowIDs, [])
    }

    private func request() -> ScrollingCaptureRequest {
        ScrollingCaptureRequest(
            window: CapturableWindow(id: 1, title: "Doc", ownerName: "App", bounds: .zero),
            maxFrames: 3,
            scrollDelta: -6,
            overlapPixels: 0
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollingCaptureTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func png(width: Int, height: Int, color: NSColor) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

private final class StubScrollingFrameCapture: ScrollingWindowFrameCapturing {
    private var frames: [Data]
    private(set) var windowIDs: [CGWindowID] = []

    init(frames: [Data]) {
        self.frames = frames
    }

    func captureWindowFrame(id: CGWindowID) throws -> Data {
        windowIDs.append(id)
        return frames.removeFirst()
    }
}

private final class StubScrollEventSender: WindowScrollEventSending {
    private(set) var windowIDs: [CGWindowID] = []
    private(set) var deltas: [Int32] = []

    func scrollWindow(id: CGWindowID, deltaY: Int32) throws {
        windowIDs.append(id)
        deltas.append(deltaY)
    }
}

private struct StubScrollingPermissions: ScrollingCapturePermissionProviding {
    let screenRecordingAllowed: Bool
    let accessibilityAllowed: Bool
}
