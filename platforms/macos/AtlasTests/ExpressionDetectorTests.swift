import XCTest
@testable import Atlas

@MainActor
final class ExpressionDetectorTests: XCTestCase {
    func testCurrency() {
        XCTAssertEqual(
            ExpressionDetector.classify("100 USD to CNY"),
            .currency(amount: 100, from: "USD", to: "CNY")
        )
        XCTAssertEqual(
            ExpressionDetector.classify("50.5 eur in usd"),
            .currency(amount: 50.5, from: "EUR", to: "USD")
        )
    }

    func testUnit() {
        XCTAssertEqual(
            ExpressionDetector.classify("5 km to miles"),
            .unit(value: 5, from: "km", to: "miles")
        )
        XCTAssertEqual(
            ExpressionDetector.classify("100 c to f"),
            .unit(value: 100, from: "c", to: "f")
        )
    }

    func testPercentageExpandsToMath() {
        XCTAssertEqual(
            ExpressionDetector.classify("15% of 320"),
            .math(expression: "(15 / 100) * 320")
        )
    }

    func testMath() {
        XCTAssertEqual(ExpressionDetector.classify("12 * 34 + 5"), .math(expression: "12 * 34 + 5"))
        XCTAssertEqual(ExpressionDetector.classify("sqrt(144)"), .math(expression: "sqrt(144)"))
        XCTAssertEqual(ExpressionDetector.classify("2^10"), .math(expression: "2^10"))
    }

    func testNegativeCases() {
        XCTAssertEqual(ExpressionDetector.classify(""), .none)
        XCTAssertEqual(ExpressionDetector.classify("hello world"), .none)
        XCTAssertEqual(ExpressionDetector.classify("screenshot"), .none)
        // 3-letter words that aren't valid units should not be unit conversions.
        XCTAssertEqual(ExpressionDetector.classify("5 cat to dog"), .none)
    }
}
