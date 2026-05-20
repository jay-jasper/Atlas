import Foundation

struct HTTPTranslationEndpointConfig: Equatable {
    let endpoint: URL
    let apiKey: String?
    let model: String?

    init(endpoint: URL, apiKey: String? = nil, model: String? = nil) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
    }
}

protocol HTTPTranslationTransporting {
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPTranslationTransport: HTTPTranslationTransporting {
    let session: URLSession
    let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 30) {
        self.session = session
        self.timeout = timeout
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, HTTPURLResponse), Error>?

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                result = .failure(error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                result = .failure(ScreenshotTranslationError.providerFailed("invalid HTTP response"))
                return
            }

            result = .success((data ?? Data(), httpResponse))
        }

        task.resume()

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            task.cancel()
            throw ScreenshotTranslationError.providerFailed("request timed out")
        }

        return try result!.get()
    }
}

struct ScreenshotHTTPTranslationProvider: ScreenshotTranslationProviding {
    let config: HTTPTranslationEndpointConfig
    let transport: HTTPTranslationTransporting

    init(config: HTTPTranslationEndpointConfig, transport: HTTPTranslationTransporting = URLSessionHTTPTranslationTransport()) {
        self.config = config
        self.transport = transport
    }

    func translate(_ request: ScreenshotTranslationRequest) throws -> ScreenshotTranslationResult {
        var urlRequest = URLRequest(url: config.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = config.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body = [
            "text": request.sourceText,
            "target_language": request.targetLanguage
        ]
        if let model = config.model {
            body["model"] = model
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: HTTPURLResponse

        do {
            (data, response) = try transport.send(urlRequest)
        } catch let error as ScreenshotTranslationError {
            throw error
        } catch {
            throw ScreenshotTranslationError.providerFailed(error.localizedDescription)
        }

        guard (200...299).contains(response.statusCode) else {
            throw ScreenshotTranslationError.httpStatus(response.statusCode)
        }

        let decoded: HTTPTranslationResponse
        do {
            decoded = try JSONDecoder().decode(HTTPTranslationResponse.self, from: data)
        } catch {
            throw ScreenshotTranslationError.invalidResponse
        }

        guard let translatedText = decoded.translatedText,
              !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScreenshotTranslationError.invalidResponse
        }

        return ScreenshotTranslationResult(
            sourceText: request.sourceText,
            translatedText: translatedText,
            targetLanguage: request.targetLanguage
        )
    }
}

private struct HTTPTranslationResponse: Decodable {
    let translatedText: String?

    private enum CodingKeys: String, CodingKey {
        case translatedText = "translated_text"
    }
}
