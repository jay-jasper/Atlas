import XCTest
@testable import Atlas

final class TokenBarLedgerTests: XCTestCase {
    func testAppendLoadAndSummarizeEntries() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let ledger = TokenBarLedger(fileURL: url)
        let entry = TokenBarUsageEntry(
            provider: .openAI,
            model: "gpt-4.1-mini",
            inputTokens: 100,
            outputTokens: 50,
            costMicrosUSD: 45_000,
            recordedAt: Date(timeIntervalSince1970: 1),
            source: "manual"
        )

        try ledger.append(entry)

        XCTAssertEqual(try ledger.load(), [entry])
        XCTAssertEqual(try ledger.summary(), TokenBarSummary(inputTokens: 100, outputTokens: 50, costMicrosUSD: 45_000))
    }
}
