import XCTest
@testable import Atlas

final class LauncherModelsTests: XCTestCase {
    func testQueryParserSplitsHeadAndRemainder() {
        let result = LauncherQueryParser.split("gh swift charts")
        XCTAssertEqual(result.head, "gh")
        XCTAssertEqual(result.remainder, "swift charts")
    }

    func testQueryParserNoRemainder() {
        let result = LauncherQueryParser.split("  calc  ")
        XCTAssertEqual(result.head, "calc")
        XCTAssertEqual(result.remainder, "")
    }

    func testFileDetailNilForMissingPath() {
        XCTAssertNil(LauncherDetail.forFile(path: "/nonexistent/definitely/missing.txt"))
        XCTAssertNil(LauncherDetail.forFile(path: ""))
    }

    func testFileDetailRowsForTempFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("launcher-detail-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let detail = try XCTUnwrap(LauncherDetail.forFile(path: url.path))
        XCTAssertEqual(detail.rows.count, 4)
        XCTAssertEqual(detail.rows[0].label, "Name")
        XCTAssertEqual(detail.rows[1].value, url.path)
        XCTAssertNil(detail.previewImagePath)
    }
}
