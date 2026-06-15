import AppKit
import ImageIO
import XCTest
@testable import Atlas

@MainActor
final class ScreenshotGIFEncoderTests: XCTestCase {
    func testEncodesAnimatedGIFWithFrameCount() throws {
        let frames = [
            ScreenshotGIFFrame(image: try image(width: 6, height: 4, color: .red), delay: 0.2),
            ScreenshotGIFFrame(image: try image(width: 6, height: 4, color: .blue), delay: 0.2),
        ]

        let data = try ImageIOScreenshotGIFEncoder().encode(frames: frames, loopCount: 0)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "com.compuserve.gif")
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
    }

    func testRejectsEmptyFrames() {
        XCTAssertThrowsError(try ImageIOScreenshotGIFEncoder().encode(frames: [], loopCount: 0)) { error in
            XCTAssertEqual(error as? ScreenshotGIFEncodingError, .emptyFrames)
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
