import XCTest
@testable import Atlas

@MainActor
final class TokenBarProviderClientTests: XCTestCase {
    func testFetchOpenAIUsageUsesInjectedTransportAndAuthorizationHeader() throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let transport = CapturingTokenBarTransport(
            data: Data(#"{"input_tokens":10,"output_tokens":4}"#.utf8),
            response: response
        )
        let client = TokenBarProviderClient(transport: transport)
        let config = TokenBarProviderConfiguration(
            provider: .openAI,
            displayName: "Work",
            endpoint: URL(string: "https://api.openai.com")!,
            apiKey: "sk-test",
            defaultModel: "gpt-4.1-mini"
        )

        let entry = try client.fetchCurrentUsage(config: config, now: Date(timeIntervalSince1970: 42))

        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(entry.inputTokens, 10)
        XCTAssertEqual(entry.outputTokens, 4)
        XCTAssertEqual(entry.source, "provider")
    }
}

final class CapturingTokenBarTransport: TokenBarHTTPTransporting {
    var lastRequest: URLRequest?
    let data: Data
    let response: HTTPURLResponse

    init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        return (data, response)
    }
}
