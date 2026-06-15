import XCTest
@testable import Atlas

@MainActor
final class WatermarkLayoutTests: XCTestCase {
    private let image = CGSize(width: 1000, height: 800)
    private let mark = CGSize(width: 100, height: 40)
    private let margin: CGFloat = 16

    func testBottomLeft() {
        let frame = WatermarkLayout.frame(position: .bottomLeft, imageSize: image, markSize: mark, margin: margin)
        XCTAssertEqual(frame.origin, CGPoint(x: 16, y: 16))
    }

    func testTopRight() {
        let frame = WatermarkLayout.frame(position: .topRight, imageSize: image, markSize: mark, margin: margin)
        XCTAssertEqual(frame.origin.x, 1000 - 100 - 16, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 800 - 40 - 16, accuracy: 0.001)
    }

    func testCenter() {
        let frame = WatermarkLayout.frame(position: .center, imageSize: image, markSize: mark, margin: margin)
        XCTAssertEqual(frame.midX, 500, accuracy: 0.001)
        XCTAssertEqual(frame.midY, 400, accuracy: 0.001)
    }

    func testTileOriginsCoverImage() {
        let origins = WatermarkLayout.tileOrigins(imageSize: CGSize(width: 300, height: 200),
                                                  markSize: CGSize(width: 100, height: 50), spacing: 0)
        // 3 columns x 4 rows = 12
        XCTAssertEqual(origins.count, 12)
        XCTAssertEqual(origins.first, .zero)
    }

    func testTileOriginsEmptyForZeroMark() {
        XCTAssertTrue(WatermarkLayout.tileOrigins(imageSize: image, markSize: .zero, spacing: 0).isEmpty)
    }
}
