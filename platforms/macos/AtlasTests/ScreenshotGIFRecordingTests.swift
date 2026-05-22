import AppKit
import XCTest
@testable import Atlas

final class ScreenshotGIFRecordingTests: XCTestCase {
    func testRecorderCapturesUntilStopRequested() throws {
        let frameSource = StubGIFFrameSource(frame: try image(width: 4, height: 4, color: .red))
        let clock = StubGIFClock(stopAfterSleeps: 2)
        let encoder = StubGIFEncoder(output: Data([0x47, 0x49, 0x46]))
        let recorder = ScreenshotGIFRecorder(
            permissionProvider: StubGIFPermissionProvider(screenRecordingAllowed: true),
            frameSource: frameSource,
            clock: clock,
            encoder: encoder
        )

        let result = try recorder.record(
            request: ScreenshotGIFRecordingRequest(
                region: CGRect(x: 10, y: 20, width: 30, height: 40),
                frameDelay: 0.1,
                maximumFrames: 10
            ),
            shouldStop: { clock.shouldStop }
        )

        XCTAssertEqual(frameSource.regions, [
            CGRect(x: 10, y: 20, width: 30, height: 40),
            CGRect(x: 10, y: 20, width: 30, height: 40),
            CGRect(x: 10, y: 20, width: 30, height: 40),
        ])
        XCTAssertEqual(clock.sleepDurations, [0.1, 0.1])
        XCTAssertEqual(encoder.receivedFrames.count, 3)
        XCTAssertEqual(result.frameCount, 3)
        XCTAssertEqual(result.gifData, Data([0x47, 0x49, 0x46]))
    }

    func testRecorderStopsAtMaximumFrames() throws {
        let frameSource = StubGIFFrameSource(frame: try image(width: 4, height: 4, color: .blue))
        let recorder = ScreenshotGIFRecorder(
            permissionProvider: StubGIFPermissionProvider(screenRecordingAllowed: true),
            frameSource: frameSource,
            clock: StubGIFClock(stopAfterSleeps: 99),
            encoder: StubGIFEncoder(output: Data([1]))
        )

        let result = try recorder.record(
            request: ScreenshotGIFRecordingRequest(
                region: CGRect(x: 0, y: 0, width: 16, height: 16),
                frameDelay: 0.05,
                maximumFrames: 2
            ),
            shouldStop: { false }
        )

        XCTAssertEqual(result.frameCount, 2)
        XCTAssertEqual(frameSource.regions.count, 2)
    }

    func testRecorderRejectsMissingScreenRecordingPermission() {
        let frameSource = StubGIFFrameSource(frame: CGImage.emptyTestImage)
        let recorder = ScreenshotGIFRecorder(
            permissionProvider: StubGIFPermissionProvider(screenRecordingAllowed: false),
            frameSource: frameSource,
            clock: StubGIFClock(stopAfterSleeps: 1),
            encoder: StubGIFEncoder(output: Data())
        )

        XCTAssertThrowsError(
            try recorder.record(
                request: ScreenshotGIFRecordingRequest(region: .zero, frameDelay: 0.1, maximumFrames: 1),
                shouldStop: { false }
            )
        ) { error in
            XCTAssertEqual(error as? ScreenshotGIFRecordingError, .screenRecordingPermissionMissing)
        }
        XCTAssertEqual(frameSource.regions, [])
    }

    func testRecorderRejectsInvalidRegionAfterPermissionCheck() {
        let recorder = ScreenshotGIFRecorder(
            permissionProvider: StubGIFPermissionProvider(screenRecordingAllowed: true),
            frameSource: StubGIFFrameSource(frame: CGImage.emptyTestImage),
            clock: StubGIFClock(stopAfterSleeps: 1),
            encoder: StubGIFEncoder(output: Data())
        )

        XCTAssertThrowsError(
            try recorder.record(
                request: ScreenshotGIFRecordingRequest(region: .zero, frameDelay: 0.1, maximumFrames: 1),
                shouldStop: { false }
            )
        ) { error in
            XCTAssertEqual(error as? ScreenshotGIFRecordingError, .invalidFrameRegion)
        }
    }

    private func image(width: Int, height: Int, color: NSColor) throws -> CGImage {
        let nsImage = NSImage(size: NSSize(width: width, height: height))
        nsImage.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        nsImage.unlockFocus()
        return try XCTUnwrap(nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }
}

private final class StubGIFFrameSource: ScreenshotGIFFrameCapturing {
    let frame: CGImage
    private(set) var regions: [CGRect] = []

    init(frame: CGImage) {
        self.frame = frame
    }

    func captureFrame(in region: CGRect) throws -> CGImage {
        regions.append(region)
        return frame
    }
}

private final class StubGIFClock: ScreenshotGIFClocking {
    let stopAfterSleeps: Int
    private(set) var sleepDurations: [TimeInterval] = []

    init(stopAfterSleeps: Int) {
        self.stopAfterSleeps = stopAfterSleeps
    }

    var shouldStop: Bool {
        sleepDurations.count >= stopAfterSleeps
    }

    func sleep(for duration: TimeInterval) {
        sleepDurations.append(duration)
    }
}

private final class StubGIFEncoder: ScreenshotGIFEncoding {
    let output: Data
    private(set) var receivedFrames: [ScreenshotGIFFrame] = []

    init(output: Data) {
        self.output = output
    }

    func encode(frames: [ScreenshotGIFFrame], loopCount: Int) throws -> Data {
        receivedFrames = frames
        return output
    }
}

private struct StubGIFPermissionProvider: ScreenshotGIFRecordingPermissionProviding {
    let screenRecordingAllowed: Bool
}

private extension CGImage {
    static var emptyTestImage: CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
