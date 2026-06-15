import AppKit
import XCTest
@testable import Atlas

@MainActor
final class SelectionPixelProbeTests: XCTestCase {
    func testHexColorFormatsRGBComponents() {
        XCTAssertEqual(SelectionPixelProbe.hexColor(red: 255, green: 8, blue: 16), "#FF0810")
    }

    func testProbeSamplesBitmapColor() throws {
        let bitmap = try makeBitmap(
            width: 2,
            height: 2,
            rgba: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255
            ]
        )

        let probe = SelectionPixelProbe.probe(
            bitmap: bitmap,
            point: CGPoint(x: 1, y: 1),
            viewSize: CGSize(width: 2, height: 2)
        )

        XCTAssertEqual(probe?.pixel, CGPoint(x: 1, y: 1))
        XCTAssertEqual(probe?.hexColor, "#FFFFFF")
    }

    func testProbeReturnsNilOutsideBitmap() throws {
        let bitmap = try makeBitmap(width: 1, height: 1, rgba: [0, 0, 0, 255])

        XCTAssertNil(SelectionPixelProbe.probe(
            bitmap: bitmap,
            point: CGPoint(x: 20, y: 20),
            viewSize: CGSize(width: 10, height: 10)
        ))
    }

    private func makeBitmap(width: Int, height: Int, rgba: [UInt8]) throws -> NSBitmapImageRep {
        let expectedByteCount = width * height * 4
        XCTAssertEqual(rgba.count, expectedByteCount)

        let data = Data(rgba)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))

        return NSBitmapImageRep(cgImage: image)
    }
}
