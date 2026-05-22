import Foundation

struct ScratchpadSummaryResult: Equatable, Sendable {
    let noteID: UUID
    let summary: String
}

protocol ScratchpadSummarizing {
    func summarize(note: ScratchpadNote) async throws -> ScratchpadSummaryResult?
}

struct DisabledScratchpadSummarizer: ScratchpadSummarizing {
    func summarize(note: ScratchpadNote) async throws -> ScratchpadSummaryResult? {
        nil
    }
}
