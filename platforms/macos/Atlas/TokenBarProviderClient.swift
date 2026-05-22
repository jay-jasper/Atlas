import Foundation

protocol TokenBarHTTPTransporting {
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse)
}

struct TokenBarURLSessionTransport: TokenBarHTTPTransporting {
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, HTTPURLResponse), Error>?

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }

            guard let response = response as? HTTPURLResponse else {
                result = .failure(CocoaError(.fileReadUnknown))
                return
            }

            result = .success((data ?? Data(), response))
        }.resume()

        semaphore.wait()
        return try result!.get()
    }
}

struct TokenBarProviderClient {
    let transport: TokenBarHTTPTransporting

    init(transport: TokenBarHTTPTransporting = TokenBarURLSessionTransport()) {
        self.transport = transport
    }

    func fetchCurrentUsage(
        config: TokenBarProviderConfiguration,
        now: Date = Date()
    ) throws -> TokenBarUsageEntry {
        var request = URLRequest(url: config.endpoint.appendingPathComponent("usage"))
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw CocoaError(.fileReadNoPermission)
        }

        let usage = try JSONDecoder().decode(TokenBarProviderUsageResponse.self, from: data)
        return TokenBarUsageEntry(
            provider: config.provider,
            model: config.defaultModel,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            costMicrosUSD: TokenBarImportService.estimateCostMicros(
                provider: config.provider,
                model: config.defaultModel,
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens
            ),
            recordedAt: now,
            source: "provider"
        )
    }
}

private struct TokenBarProviderUsageResponse: Decodable {
    let inputTokens: Int
    let outputTokens: Int

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}
