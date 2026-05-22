import XCTest
@testable import Atlas

final class ScratchpadSummaryServiceTests: XCTestCase {
    func testDisabledSummarizerReturnsNil() async throws {
        let note = ScratchpadNote(title: "Design", markdown: "# Design\nDetails")
        let summarizer = DisabledScratchpadSummarizer()

        let result = try await summarizer.summarize(note: note)

        XCTAssertNil(result)
    }

    func testInjectedSummarizerCanReturnSummary() async throws {
        let note = ScratchpadNote(title: "Design", markdown: "# Design\nDetails")
        let summarizer = FakeScratchpadSummarizer(summary: "Summarized design details.")

        let result = try await summarizer.summarize(note: note)

        XCTAssertEqual(result, ScratchpadSummaryResult(noteID: note.id, summary: "Summarized design details."))
    }
}

private struct FakeScratchpadSummarizer: ScratchpadSummarizing {
    let summary: String

    func summarize(note: ScratchpadNote) async throws -> ScratchpadSummaryResult? {
        ScratchpadSummaryResult(noteID: note.id, summary: summary)
    }
}
