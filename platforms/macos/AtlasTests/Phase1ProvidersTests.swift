import XCTest
@testable import Atlas

@MainActor
final class IdentifierProviderTests: XCTestCase {
    func testUUIDGeneratesAndCopies() {
        var copied: [String] = []
        let provider = IdentifierProvider(copy: { copied.append($0) }, makeUUID: { "FIXED-UUID" })
        let results = provider.results(for: "uuid")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "FIXED-UUID")
        if case .execute(let run) = results[0].action { run() }
        XCTAssertEqual(copied, ["FIXED-UUID"])
    }

    func testNanoIDRespectsLength() {
        let provider = IdentifierProvider(randomByte: { 0 })
        let results = provider.results(for: "nanoid 10")
        XCTAssertEqual(results.first?.title.count, 10)
    }

    func testNonKeywordReturnsEmpty() {
        XCTAssertTrue(IdentifierProvider().results(for: "hello").isEmpty)
    }
}

@MainActor
final class PasswordGeneratorProviderTests: XCTestCase {
    func testDefaultLength() {
        let provider = PasswordGeneratorProvider(pick: { _ in 0 })
        XCTAssertEqual(provider.results(for: "password").first?.title.count, 16)
    }

    func testCustomLengthAndSymbols() {
        let provider = PasswordGeneratorProvider(pick: { _ in 0 })
        let result = provider.results(for: "password 24 symbols").first
        XCTAssertEqual(result?.title.count, 24)
        XCTAssertTrue(result?.subtitle?.contains("symbols") ?? false)
    }

    func testNonKeywordReturnsEmpty() {
        XCTAssertTrue(PasswordGeneratorProvider().results(for: "passw").isEmpty)
    }
}

@MainActor
final class HashGeneratorProviderTests: XCTestCase {
    func testKnownMD5() {
        XCTAssertEqual(HashGeneratorProvider.hash("hello", with: .md5), "5d41402abc4b2a76b9719d911017c592")
    }

    func testKnownSHA256() {
        XCTAssertEqual(
            HashGeneratorProvider.hash("hello", with: .sha256),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    func testProviderProducesDigest() {
        let result = HashGeneratorProvider().results(for: "hash md5 hello").first
        XCTAssertEqual(result?.title, "5d41402abc4b2a76b9719d911017c592")
    }

    func testUnknownAlgorithmReturnsEmpty() {
        XCTAssertTrue(HashGeneratorProvider().results(for: "hash crc32 hi").isEmpty)
    }
}

@MainActor
final class EncodingProviderTests: XCTestCase {
    func testBase64RoundTrip() {
        let provider = EncodingProvider()
        XCTAssertEqual(provider.results(for: "b64 hello").first?.title, "aGVsbG8=")
        XCTAssertEqual(provider.results(for: "b64decode aGVsbG8=").first?.title, "hello")
    }

    func testURLEncode() {
        XCTAssertEqual(EncodingProvider().results(for: "urlencode a b").first?.title, "a%20b")
    }

    func testNonKeywordReturnsEmpty() {
        XCTAssertTrue(EncodingProvider().results(for: "hello world").isEmpty)
    }
}

@MainActor
final class JSONFormatProviderTests: XCTestCase {
    func testFormatsValidJSON() {
        var copied: [String] = []
        let provider = JSONFormatProvider(copy: { copied.append($0) })
        let results = provider.results(for: "{\"b\":1,\"a\":2}")
        XCTAssertEqual(results.first?.title, "Format JSON")
        if case .execute(let run)? = results.first?.action { run() }
        XCTAssertTrue(copied.first?.contains("\"a\" : 2") ?? false)
    }

    func testInvalidJSON() {
        XCTAssertEqual(JSONFormatProvider().results(for: "{not json").first?.title, "Invalid JSON")
    }

    func testNonJSONReturnsEmpty() {
        XCTAssertTrue(JSONFormatProvider().results(for: "hello").isEmpty)
    }
}

@MainActor
final class LoremIpsumProviderTests: XCTestCase {
    func testWordsCount() {
        let result = LoremIpsumProvider().results(for: "lorem 5w").first
        XCTAssertTrue(result?.title.contains("5 words") ?? false)
    }

    func testParseSpec() {
        XCTAssertEqual(LoremIpsumProvider.parseSpec("3p").0, 3)
        if case .paragraphs = LoremIpsumProvider.parseSpec("3p").1 {} else { XCTFail() }
        if case .words = LoremIpsumProvider.parseSpec("7w").1 {} else { XCTFail() }
    }

    func testNonKeywordReturnsEmpty() {
        XCTAssertTrue(LoremIpsumProvider().results(for: "text").isEmpty)
    }
}

@MainActor
final class ColorFormatProviderTests: XCTestCase {
    func testHexToRGB() {
        XCTAssertEqual(ColorFormatProvider().results(for: "#FF5733 to rgb").first?.title, "rgb(255, 87, 51)")
    }

    func testRGBToHex() {
        XCTAssertEqual(ColorFormatProvider().results(for: "rgb(255,87,51) to hex").first?.title, "#FF5733")
    }

    func testHexToHSL() {
        // #FF0000 -> hsl(0, 100%, 50%)
        XCTAssertEqual(ColorFormatProvider().results(for: "#FF0000 to hsl").first?.title, "hsl(0, 100%, 50%)")
    }

    func testInvalidReturnsEmpty() {
        XCTAssertTrue(ColorFormatProvider().results(for: "hello to rgb").isEmpty)
    }
}

@MainActor
final class RegexTesterProviderTests: XCTestCase {
    func testMatchWithGroup() {
        let result = RegexTesterProvider().results(for: "regex /(\\d+)/ on abc123").first
        XCTAssertTrue(result?.title.contains("123") ?? false)
    }

    func testNoMatch() {
        XCTAssertEqual(RegexTesterProvider().results(for: "regex /z+/ on abc").first?.title, "No matches")
    }

    func testParse() {
        let parsed = RegexTesterProvider.parse("/\\d+/ on hello123")
        XCTAssertEqual(parsed?.pattern, "\\d+")
        XCTAssertEqual(parsed?.text, "hello123")
    }
}

@MainActor
final class TimezoneProviderTests: XCTestCase {
    func testParseTime() {
        XCTAssertEqual(TimezoneProvider.parseTime("9am").map { [$0.0, $0.1] }, [9, 0])
        XCTAssertEqual(TimezoneProvider.parseTime("9:30pm").map { [$0.0, $0.1] }, [21, 30])
        XCTAssertEqual(TimezoneProvider.parseTime("15:00").map { [$0.0, $0.1] }, [15, 0])
    }

    func testZoneAlias() {
        XCTAssertEqual(TimezoneProvider.zone(for: "tokyo")?.identifier, "Asia/Tokyo")
        XCTAssertEqual(TimezoneProvider.zone(for: "pst")?.identifier, "America/Los_Angeles")
    }

    func testConversionProducesResult() {
        let results = TimezoneProvider().results(for: "9am utc in tokyo")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].title.contains("PM") || results[0].title.contains("AM"))
    }

    func testNonTimeReturnsEmpty() {
        XCTAssertTrue(TimezoneProvider().results(for: "hello").isEmpty)
    }
}

@MainActor
final class EmojiProviderTests: XCTestCase {
    func testSearchByKeyword() {
        var copied: [String] = []
        let provider = EmojiProvider(copy: { copied.append($0) })
        let results = provider.results(for: "emoji fire")
        XCTAssertTrue(results.contains { $0.title.contains("🔥") })
        if let fire = results.first(where: { $0.title.contains("🔥") }),
           case .execute(let run) = fire.action {
            run()
            XCTAssertEqual(copied, ["🔥"])
        } else {
            XCTFail("expected fire emoji")
        }
    }

    func testNonKeywordReturnsEmpty() {
        XCTAssertTrue(EmojiProvider().results(for: "fire").isEmpty)
    }
}
