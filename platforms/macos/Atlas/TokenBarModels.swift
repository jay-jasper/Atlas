import Foundation

enum TokenBarProvider: String, Codable, Equatable, CaseIterable, Sendable {
    case openAI
    case claude

    var title: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .claude:
            return "Claude"
        }
    }
}

struct TokenBarProviderConfiguration: Codable, Equatable, Sendable {
    var provider: TokenBarProvider
    var displayName: String
    var endpoint: URL
    var apiKey: String
    var defaultModel: String
}

struct TokenBarUsageEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var provider: TokenBarProvider
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var costMicrosUSD: Int
    var recordedAt: Date
    var source: String

    init(
        id: UUID = UUID(),
        provider: TokenBarProvider,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        costMicrosUSD: Int,
        recordedAt: Date,
        source: String
    ) {
        self.id = id
        self.provider = provider
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.costMicrosUSD = max(0, costMicrosUSD)
        self.recordedAt = recordedAt
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TokenBarSummary: Equatable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var costMicrosUSD: Int

    static let empty = TokenBarSummary(inputTokens: 0, outputTokens: 0, costMicrosUSD: 0)
}
