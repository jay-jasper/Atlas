import XCTest
@testable import Atlas

@MainActor
final class ExpressionEvaluatorTests: XCTestCase {
    private let evaluator = NativeExpressionEvaluator()

    func testBasicArithmetic() {
        XCTAssertEqual(evaluator.evaluate("12 * 34 + 5"), 413)
    }

    func testOperatorPrecedence() {
        XCTAssertEqual(evaluator.evaluate("2 + 3 * 4"), 14)
    }

    func testParentheses() {
        XCTAssertEqual(evaluator.evaluate("(2 + 3) * 4"), 20)
    }

    func testPowerIsRightAssociative() {
        XCTAssertEqual(evaluator.evaluate("2 ^ 3 ^ 2"), 512) // 2^(3^2)
    }

    func testUnaryMinus() {
        XCTAssertEqual(evaluator.evaluate("-5 + 3"), -2)
    }

    func testFunctions() {
        XCTAssertEqual(evaluator.evaluate("sqrt(144)"), 12)
        XCTAssertEqual(evaluator.evaluate("abs(-7)"), 7)
        XCTAssertEqual(evaluator.evaluate("floor(3.9)"), 3)
    }

    func testConstants() {
        XCTAssertEqual(try XCTUnwrap(evaluator.evaluate("pi")), Double.pi, accuracy: 1e-9)
    }

    func testDivisionByZeroReturnsNil() {
        XCTAssertNil(evaluator.evaluate("1 / 0"))
    }

    func testMalformedReturnsNil() {
        XCTAssertNil(evaluator.evaluate("12 *"))
        XCTAssertNil(evaluator.evaluate("(1 + 2"))
        XCTAssertNil(evaluator.evaluate("@#$"))
        XCTAssertNil(evaluator.evaluate(""))
    }
}
