import XCTest
@testable import Atlas

@MainActor
final class AIChatBridgeTests: XCTestCase {
    func testTitleTruncation() {
        XCTAssertEqual(AIChatBridge.title(for: "hello"), "hello")
        XCTAssertEqual(AIChatBridge.title(for: "first line\nsecond"), "first line")
        let long = String(repeating: "字", count: 30)
        let title = AIChatBridge.title(for: long)
        XCTAssertEqual(title.count, 25) // 24 + ellipsis
        XCTAssertTrue(title.hasSuffix("…"))
    }
}
