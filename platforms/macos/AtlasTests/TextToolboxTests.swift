import XCTest
@testable import Atlas

@MainActor
final class TextToolboxTests: XCTestCase {
    func testUppercase() {
        XCTAssertEqual(TextToolboxMode.uppercase.transform("hello World"), "HELLO WORLD")
    }

    func testLowercase() {
        XCTAssertEqual(TextToolboxMode.lowercase.transform("Hello WORLD"), "hello world")
    }

    func testTrimWhitespace() {
        XCTAssertEqual(TextToolboxMode.trimmed.transform("  hello  \n"), "hello")
    }

    func testFormatValidJSON() {
        let input = """
        {"b":2,"a":1}
        """
        let output = TextToolboxMode.jsonPretty.transform(input)
        XCTAssertTrue(output.contains("\"a\" : 1"))
        XCTAssertTrue(output.contains("\"b\" : 2"))
    }

    func testFormatInvalidJSONReturnsError() {
        XCTAssertEqual(TextToolboxMode.jsonPretty.transform("not json"), "Invalid JSON")
    }

    func testBase64EncodeAndDecode() {
        let original = "Hello, Atlas!"
        let encoded = TextToolboxMode.base64Encode.transform(original)
        let decoded = TextToolboxMode.base64Decode.transform(encoded)
        XCTAssertFalse(encoded.isEmpty)
        XCTAssertEqual(decoded, original)
    }

    func testBase64DecodeInvalidInput() {
        XCTAssertEqual(TextToolboxMode.base64Decode.transform("!!!"), "Invalid Base64")
    }

    func testURLEncodeAndDecode() {
        let original = "hello world & more"
        let encoded = TextToolboxMode.urlEncode.transform(original)
        let decoded = TextToolboxMode.urlDecode.transform(encoded)
        XCTAssertTrue(encoded.contains("%20") || encoded.contains("+"))
        XCTAssertEqual(decoded, original)
    }

    func testTimestampToISO8601() {
        let result = TextToolboxMode.timestampISO.transform("0")
        XCTAssertTrue(result.hasPrefix("1970-01-01"))
    }

    func testTimestampInvalidInput() {
        XCTAssertEqual(TextToolboxMode.timestampISO.transform("not-a-number"), "Invalid timestamp")
    }
}
