import XCTest
@testable import Atlas

final class ScreenshotBeautifyTests: XCTestCase {
    func testPaddingClampsToRange() {
        var options = BeautifyOptions()
        options.paddingFraction = 0.0001
        let small = ScreenshotBeautifyRenderer.padding(baseSize: CGSize(width: 4000, height: 4000), options: options)
        XCTAssertEqual(small, 4000 * 0.02, accuracy: 0.5)

        options.paddingFraction = 0.9
        let large = ScreenshotBeautifyRenderer.padding(baseSize: CGSize(width: 1000, height: 1000), options: options)
        XCTAssertEqual(large, 250, accuracy: 0.5)

        options.paddingFraction = 0.08
        let floor = ScreenshotBeautifyRenderer.padding(baseSize: CGSize(width: 100, height: 100), options: options)
        XCTAssertEqual(floor, 32)
    }

    func testOutputSizeOriginalAspect() {
        var options = BeautifyOptions()
        options.paddingFraction = 0.1
        options.windowFrame = false
        options.aspect = .original
        let size = ScreenshotBeautifyRenderer.outputSize(baseSize: CGSize(width: 1000, height: 500), options: options)
        // padding = 500 * 0.1 = 50
        XCTAssertEqual(size, CGSize(width: 1100, height: 600))
    }

    func testOutputSizeExpandsToSquare() {
        var options = BeautifyOptions()
        options.paddingFraction = 0.1
        options.aspect = .square
        let size = ScreenshotBeautifyRenderer.outputSize(baseSize: CGSize(width: 1000, height: 500), options: options)
        XCTAssertEqual(size.width, size.height)
        XCTAssertEqual(size.width, 1100)
    }

    func testOutputSizeIncludesWindowFrameBar() {
        var options = BeautifyOptions()
        options.paddingFraction = 0.1
        options.windowFrame = true
        options.aspect = .original
        let bar = ScreenshotBeautifyRenderer.frameBarHeight(baseWidth: 1000)
        let size = ScreenshotBeautifyRenderer.outputSize(baseSize: CGSize(width: 1000, height: 500), options: options)
        XCTAssertEqual(size.height, (600 + bar).rounded())
    }

    func testFrameBarHeightClamps() {
        XCTAssertEqual(ScreenshotBeautifyRenderer.frameBarHeight(baseWidth: 100), 28)
        XCTAssertEqual(ScreenshotBeautifyRenderer.frameBarHeight(baseWidth: 10000), 56)
    }

    func testOptionsRoundTripThroughDefaults() {
        let defaults = UserDefaults(suiteName: "beautify-tests")!
        defaults.removePersistentDomain(forName: "beautify-tests")

        var options = BeautifyOptions()
        options.backgroundPresetIndex = 3
        options.shadow = .heavy
        options.windowFrame = true
        options.aspect = .sixteenNine
        options.saveAsLastUsed(defaults: defaults)

        let loaded = BeautifyOptions.loadLastUsed(defaults: defaults)
        XCTAssertEqual(loaded, options)
    }

    func testRenderProducesDecodableLargerImage() throws {
        // 20×10 red PNG.
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 10).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = rep.representation(using: .png, properties: [:])!

        let out = ScreenshotBeautifyRenderer.renderPNG(png, options: BeautifyOptions())
        let outRep = try XCTUnwrap(NSBitmapImageRep(data: out))
        XCTAssertGreaterThan(outRep.pixelsWide, 20)
        XCTAssertGreaterThan(outRep.pixelsHigh, 10)
    }
}
