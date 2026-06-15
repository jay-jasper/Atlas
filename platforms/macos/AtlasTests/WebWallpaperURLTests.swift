import XCTest
@testable import Atlas

@MainActor
final class WebWallpaperURLTests: XCTestCase {
    func testAddsHttpsScheme() {
        XCTAssertEqual(WebWallpaperURL.normalize("example.com")?.absoluteString, "https://example.com")
    }

    func testKeepsExistingScheme() {
        XCTAssertEqual(WebWallpaperURL.normalize("http://test.org/path")?.absoluteString, "http://test.org/path")
    }

    func testAllowsLocalhost() {
        XCTAssertEqual(WebWallpaperURL.normalize("localhost:8080")?.host, "localhost")
    }

    func testRejectsEmpty() {
        XCTAssertNil(WebWallpaperURL.normalize("   "))
    }

    func testRejectsNonWebScheme() {
        XCTAssertNil(WebWallpaperURL.normalize("file:///etc/passwd"))
        XCTAssertNil(WebWallpaperURL.normalize("ftp://example.com"))
    }

    func testRejectsHostWithoutDot() {
        XCTAssertNil(WebWallpaperURL.normalize("notadomain"))
    }

    func testPresetsAreValid() {
        for preset in WebWallpaperURL.presets {
            XCTAssertNotNil(WebWallpaperURL.normalize(preset.url), "preset \(preset.name) should normalize")
        }
    }
}
