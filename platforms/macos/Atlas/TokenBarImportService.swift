import Foundation

struct TokenBarImportService {
    private let iso = ISO8601DateFormatter()

    func importCSV(_ data: Data) throws -> [TokenBarUsageEntry] {
        let text = String(decoding: data, as: UTF8.self)
        return try text.split(separator: "\n").dropFirst().map { row in
            let columns = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 5,
                  let provider = TokenBarProvider(rawValue: columns[0]),
                  let input = Int(columns[2]),
                  let output = Int(columns[3]),
                  let recordedAt = iso.date(from: columns[4])
            else {
                throw CocoaError(.fileReadCorruptFile)
            }

            return TokenBarUsageEntry(
                provider: provider,
                model: columns[1],
                inputTokens: input,
                outputTokens: output,
                costMicrosUSD: Self.estimateCostMicros(
                    provider: provider,
                    model: columns[1],
                    inputTokens: input,
                    outputTokens: output
                ),
                recordedAt: recordedAt,
                source: "manual-import"
            )
        }
    }

    static func estimateCostMicros(
        provider: TokenBarProvider,
        model: String,
        inputTokens: Int,
        outputTokens: Int
    ) -> Int {
        switch (provider, model) {
        case (.openAI, "gpt-4.1-mini"):
            return inputTokens * 2 / 10 + outputTokens * 6 / 10
        case (.claude, "claude-3-5-haiku"):
            return inputTokens * 4 / 10 + outputTokens * 12 / 10
        default:
            return 0
        }
    }
}
