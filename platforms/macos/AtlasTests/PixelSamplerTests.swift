import XCTest
import CoreGraphics
@testable import Atlas

@MainActor
final class PixelSamplerTests: XCTestCase {
    /// Builds a solid-color test image.
    private func solidImage(r: Int, g: Int, b: Int, size: Int = 4) -> CGImage {
        let bytesPerRow = 4 * size
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * size)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = UInt8(r); pixels[i + 1] = UInt8(g); pixels[i + 2] = UInt8(b); pixels[i + 3] = 255
        }
        let context = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    func testSamplesSolidColor() {
        let image = solidImage(r: 255, g: 87, b: 51)
        let rgb = PixelSampler.color(at: CGPoint(x: 1, y: 1), in: image)
        XCTAssertEqual(rgb, ColorFormatProvider.RGB(r: 255, g: 87, b: 51))
    }

    func testOutOfBoundsReturnsNil() {
        let image = solidImage(r: 0, g: 0, b: 0, size: 2)
        XCTAssertNil(PixelSampler.color(at: CGPoint(x: 5, y: 5), in: image))
        XCTAssertNil(PixelSampler.color(at: CGPoint(x: -1, y: 0), in: image))
    }

    func testDescribeFormat() {
        let desc = PixelSampler.describe(ColorFormatProvider.RGB(r: 255, g: 87, b: 51))
        XCTAssertEqual(desc, "#FF5733 · rgb(255, 87, 51)")
    }

    func testServiceSamplesNormalizedPoint() {
        let service = ColorSamplerService()
        // Without a loaded image, sampling is a no-op (no crash).
        service.sample(atNormalized: CGPoint(x: 0.5, y: 0.5))
        XCTAssertNil(service.sampledHex)
    }
}
