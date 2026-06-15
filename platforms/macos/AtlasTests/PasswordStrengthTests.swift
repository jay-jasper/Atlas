import XCTest
@testable import Atlas

@MainActor
final class PasswordStrengthTests: XCTestCase {
    func testEmptyIsVeryWeak() {
        XCTAssertEqual(PasswordStrength.assess("").rating, .veryWeak)
    }

    func testShortLowercaseIsWeak() {
        let rating = PasswordStrength.assess("abc").rating
        XCTAssertTrue([.veryWeak, .weak].contains(rating))
    }

    func testLongMixedIsStrong() {
        let assessment = PasswordStrength.assess("Tr0ub4dour&3xpl0it!Quux")
        XCTAssertGreaterThan(assessment.bits, 60)
        XCTAssertTrue([.strong, .veryStrong].contains(assessment.rating))
    }

    func testRepeatedCharsArePenalized() {
        let diverse = PasswordStrength.assess("aB3$xY9!").bits
        let repetitive = PasswordStrength.assess("aaaaaaaa").bits
        XCTAssertGreaterThan(diverse, repetitive)
    }

    func testSequentialRunDetection() {
        XCTAssertTrue(PasswordStrength.hasSequentialRun("xx1234xx"))
        XCTAssertTrue(PasswordStrength.hasSequentialRun("abcd"))
        XCTAssertFalse(PasswordStrength.hasSequentialRun("a1b2c3"))
    }

    func testRatingThresholds() {
        XCTAssertEqual(PasswordStrength.rating(forBits: 10), .veryWeak)
        XCTAssertEqual(PasswordStrength.rating(forBits: 50), .fair)
        XCTAssertEqual(PasswordStrength.rating(forBits: 100), .veryStrong)
    }
}
