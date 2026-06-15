import XCTest
@testable import Atlas

@MainActor
final class TOTPGeneratorTests: XCTestCase {
    // RFC 6238 reference secret: ASCII "12345678901234567890" in base32.
    private let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    func testRFC6238Vectors() {
        // T = 59s -> 8-digit SHA1 TOTP 94287082 (RFC 6238 Appendix B).
        XCTAssertEqual(
            TOTPGenerator.code(secretBase32: secret, date: Date(timeIntervalSince1970: 59), digits: 8),
            "94287082"
        )
        // T = 1111111109s -> 07081804.
        XCTAssertEqual(
            TOTPGenerator.code(secretBase32: secret, date: Date(timeIntervalSince1970: 1111111109), digits: 8),
            "07081804"
        )
    }

    func testSixDigitDefault() {
        let code = TOTPGenerator.code(secretBase32: secret, date: Date(timeIntervalSince1970: 59))
        XCTAssertEqual(code?.count, 6)
        XCTAssertEqual(code, "287082") // low 6 digits of 94287082
    }

    func testSecondsRemaining() {
        XCTAssertEqual(TOTPGenerator.secondsRemaining(date: Date(timeIntervalSince1970: 55)), 5)
        XCTAssertEqual(TOTPGenerator.secondsRemaining(date: Date(timeIntervalSince1970: 30)), 30)
    }

    func testInvalidBase32ReturnsNil() {
        XCTAssertNil(TOTPGenerator.code(secretBase32: "not base32 !!!", date: Date()))
    }

    func testBase32DecodeKnownValue() {
        XCTAssertEqual(TOTPGenerator.base32Decode("MZXW6==="), Data("foo".utf8))
    }
}

@MainActor
final class TOTPAccountTests: XCTestCase {
    func testParseOtpauthURI() {
        let uri = "otpauth://totp/GitHub:alice?secret=GEZDGNBVGY3TQOJQ&issuer=GitHub&digits=6&period=30"
        let account = TOTPAccount.parse(otpauthURI: uri)
        XCTAssertEqual(account?.issuer, "GitHub")
        XCTAssertEqual(account?.label, "alice")
        XCTAssertEqual(account?.secret, "GEZDGNBVGY3TQOJQ")
        XCTAssertEqual(account?.digits, 6)
    }

    func testParseRejectsInvalidScheme() {
        XCTAssertNil(TOTPAccount.parse(otpauthURI: "https://example.com"))
    }

    func testParseRejectsInvalidSecret() {
        XCTAssertNil(TOTPAccount.parse(otpauthURI: "otpauth://totp/x?secret=!!!"))
    }

    func testValidity() {
        XCTAssertTrue(TOTPAccount(issuer: "X", label: "y", secret: "GEZDGNBVGY3TQOJQ").isValid)
        XCTAssertFalse(TOTPAccount(issuer: "", label: "y", secret: "GEZDGNBVGY3TQOJQ").isValid)
        XCTAssertFalse(TOTPAccount(issuer: "X", label: "y", secret: "!!!").isValid)
    }
}

@MainActor
final class TOTPServiceTests: XCTestCase {
    func testAddAndDelete() {
        let service = TOTPService(store: InMemoryTOTPStore())
        let account = TOTPAccount(issuer: "GitHub", label: "alice", secret: "GEZDGNBVGY3TQOJQ")
        service.add(account)
        XCTAssertEqual(service.accounts.count, 1)
        service.delete(id: account.id)
        XCTAssertTrue(service.accounts.isEmpty)
    }

    func testAddFromURI() {
        let service = TOTPService(store: InMemoryTOTPStore())
        service.addFromURI("otpauth://totp/Acme:bob?secret=GEZDGNBVGY3TQOJQ&issuer=Acme")
        XCTAssertEqual(service.accounts.first?.issuer, "Acme")
    }

    func testInvalidAddSetsStatus() {
        let service = TOTPService(store: InMemoryTOTPStore())
        service.addFromURI("not a uri")
        XCTAssertFalse(service.statusMessage.isEmpty)
        XCTAssertTrue(service.accounts.isEmpty)
    }

    func testCodeGeneration() {
        let service = TOTPService(store: InMemoryTOTPStore())
        let account = TOTPAccount(issuer: "X", label: "y", secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        XCTAssertEqual(service.code(for: account, at: Date(timeIntervalSince1970: 59)), "287082")
    }
}
