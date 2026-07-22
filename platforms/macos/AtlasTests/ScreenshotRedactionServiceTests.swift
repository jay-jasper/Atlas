import XCTest
@testable import Atlas

final class ScreenshotRedactionServiceTests: XCTestCase {
    // MARK: PII classification

    func testDetectsEmail() {
        let matches = PIIClassifier.matches(in: "联系 support@example.com 获取帮助")
        XCTAssertEqual(matches.map(\.kind), [.email])
        XCTAssertEqual(matches.first?.text, "support@example.com")
    }

    func testDetectsMainlandMobile() {
        let matches = PIIClassifier.matches(in: "电话 13812345678 或 +86 139 1234 5678")
        XCTAssertEqual(matches.map(\.kind), [.phone, .phone])
    }

    func testRejectsShortNumberAsPhone() {
        XCTAssertTrue(PIIClassifier.matches(in: "端口 8080 版本 1.2.3").isEmpty)
    }

    func testDetectsCardNumberWithLuhn() {
        // Valid Visa test number.
        let matches = PIIClassifier.matches(in: "卡号 4111 1111 1111 1111 已绑定")
        XCTAssertEqual(matches.map(\.kind), [.cardNumber])
    }

    func testRejectsCardNumberFailingLuhn() {
        let matches = PIIClassifier.matches(in: "订单 4111 1111 1111 1112 处理中")
        XCTAssertFalse(matches.contains { $0.kind == .cardNumber })
    }

    func testDetectsAPIKeys() {
        let sk = PIIClassifier.matches(in: "OPENAI_KEY=sk-abcdefghijklmnop1234")
        XCTAssertEqual(sk.map(\.kind), [.apiKey])

        let ghp = PIIClassifier.matches(in: "token ghp_abcdefghijklmnopqrst1234")
        XCTAssertEqual(ghp.map(\.kind), [.apiKey])

        let akia = PIIClassifier.matches(in: "AKIAIOSFODNN7EXAMPLE in config")
        XCTAssertEqual(akia.map(\.kind), [.apiKey])
    }

    func testDetectsIPAddress() {
        let matches = PIIClassifier.matches(in: "server 192.168.1.100 online")
        XCTAssertEqual(matches.map(\.kind), [.ipAddress])
    }

    func testRejectsVersionStringAsIP() {
        let matches = PIIClassifier.matches(in: "version 1.2.3.4.5")
        XCTAssertFalse(matches.contains { $0.kind == .ipAddress })
    }

    func testOptionsDisableCategories() {
        var options = PIIClassifier.Options.all
        options.email = false
        let matches = PIIClassifier.matches(in: "mail a@b.com ip 10.0.0.1", options: options)
        XCTAssertEqual(matches.map(\.kind), [.ipAddress])
    }

    func testLuhn() {
        XCTAssertTrue(PIIClassifier.passesLuhn("4111111111111111"))
        XCTAssertTrue(PIIClassifier.passesLuhn("5500005555555559"))
        XCTAssertFalse(PIIClassifier.passesLuhn("4111111111111112"))
        XCTAssertFalse(PIIClassifier.passesLuhn("1234"))
        XCTAssertFalse(PIIClassifier.passesLuhn("abcd1111111111111"))
    }

    // MARK: Sub-box estimation

    func testSubBoxFractionsLine() {
        let line = "AAAABBBBCC"
        let start = line.index(line.startIndex, offsetBy: 4)
        let end = line.index(start, offsetBy: 4)
        let box = PIIClassifier.subBox(
            lineBox: CGRect(x: 0.2, y: 0.5, width: 0.5, height: 0.1),
            line: line,
            range: start..<end
        )
        XCTAssertEqual(box.minX, 0.4, accuracy: 0.0001)
        XCTAssertEqual(box.width, 0.2, accuracy: 0.0001)
        XCTAssertEqual(box.minY, 0.5)
        XCTAssertEqual(box.height, 0.1)
    }

    // MARK: Coordinate mapping

    func testCanvasRectFlipsVisionYAxis() {
        // Vision box occupying the top-left quarter (origin bottom-left).
        let normalized = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        let imageRect = CGRect(x: 10, y: 20, width: 200, height: 100)
        let rect = RedactionCoordinateMapper.canvasRect(normalized: normalized, renderedImageRect: imageRect)
        XCTAssertEqual(rect, CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    func testFittedImageRectCentersAndScales() {
        let rect = RedactionCoordinateMapper.fittedImageRect(
            imageSize: CGSize(width: 200, height: 100),
            canvasSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 25, width: 100, height: 50))
    }
}
