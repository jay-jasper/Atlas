import AppKit
import XCTest
@testable import Atlas

final class ScreenshotImageStitcherTests: XCTestCase {
    func testStitchesFramesVerticallyWithoutOverlap() throws {
        let red = try png(width: 8, height: 5, color: .red)
        let blue = try png(width: 8, height: 7, color: .blue)

        let output = try VerticalScreenshotImageStitcher().stitch(
            frames: [red, blue],
            overlapPixels: 0
        )

        XCTAssertEqual(try dimensions(of: output), CGSize(width: 8, height: 12))
    }

    func testStitchesFramesWithFixedOverlapTrim() throws {
        let first = try png(width: 10, height: 8, color: .red)
        let second = try png(width: 10, height: 8, color: .blue)
        let third = try png(width: 10, height: 8, color: .green)

        let output = try VerticalScreenshotImageStitcher().stitch(
            frames: [first, second, third],
            overlapPixels: 3
        )

        XCTAssertEqual(try dimensions(of: output), CGSize(width: 10, height: 18))
    }

    func testRejectsEmptyFrameList() {
        XCTAssertThrowsError(
            try VerticalScreenshotImageStitcher().stitch(frames: [], overlapPixels: 0)
        ) { error in
            XCTAssertEqual(error as? ScreenshotImageStitchingError, .emptyFrames)
        }
    }

    private func png(width: Int, height: Int, color: NSColor) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw XCTSkip("Could not create test PNG")
        }
        return png
    }

    private func dimensions(of pngData: Data) throws -> CGSize {
        let image = try XCTUnwrap(NSImage(data: pngData))
        return image.size
    }
}
