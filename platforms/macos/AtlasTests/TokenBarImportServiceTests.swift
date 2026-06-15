import XCTest
@testable import Atlas

@MainActor
final class TokenBarImportServiceTests: XCTestCase {
    func testImportsCSVRowsAndComputesCost() throws {
        let csv = """
        provider,model,input_tokens,output_tokens,recorded_at
        openAI,gpt-4.1-mini,1000,500,2026-05-22T10:00:00Z
        claude,claude-3-5-haiku,2000,1000,2026-05-22T11:00:00Z
        """
        let entries = try TokenBarImportService().importCSV(Data(csv.utf8))

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].costMicrosUSD, 500)
        XCTAssertEqual(entries[1].costMicrosUSD, 2_000)
        XCTAssertEqual(entries[0].source, "manual-import")
    }
}
