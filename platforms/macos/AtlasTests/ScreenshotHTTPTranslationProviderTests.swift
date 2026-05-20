import Foundation
import XCTest
@testable import Atlas

final class ScreenshotHTTPTranslationProviderTests: XCTestCase {
    func testBuildsPostRequestWithJsonBodyAndAuthorizationHeader() throws {
        let endpoint = URL(string: "https://translation.example.test/v1/translate")!
        let transport = StubHTTPTranslationTransport(
            data: Data(#"{"translated_text":"Bonjour"}"#.utf8),
            response: httpResponse(url: endpoint, statusCode: 200)
        )
        let provider = ScreenshotHTTPTranslationProvider(
            config: HTTPTranslationEndpointConfig(
                endpoint: endpoint,
                apiKey: "test-key",
                model: "atlas-test-model"
            ),
            transport: transport
        )

        let result = try provider.translate(
            ScreenshotTranslationRequest(sourceText: "Hello", targetLanguage: "fr")
        )

        XCTAssertEqual(result.sourceText, "Hello")
        XCTAssertEqual(result.translatedText, "Bonjour")
        XCTAssertEqual(result.targetLanguage, "fr")
        XCTAssertEqual(transport.receivedRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.receivedRequest?.url, endpoint)
        XCTAssertEqual(transport.receivedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(transport.receivedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let body = try XCTUnwrap(transport.receivedRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["text"], "Hello")
        XCTAssertEqual(json["target_language"], "fr")
        XCTAssertEqual(json["model"], "atlas-test-model")
    }

    func testOmitsAuthorizationAndModelWhenNotConfigured() throws {
        let endpoint = URL(string: "https://translation.example.test/v1/translate")!
        let transport = StubHTTPTranslationTransport(
            data: Data(#"{"translated_text":"Hello"}"#.utf8),
            response: httpResponse(url: endpoint, statusCode: 200)
        )
        let provider = ScreenshotHTTPTranslationProvider(
            config: HTTPTranslationEndpointConfig(endpoint: endpoint),
            transport: transport
        )

        _ = try provider.translate(
            ScreenshotTranslationRequest(sourceText: "Hola", targetLanguage: "English")
        )

        XCTAssertNil(transport.receivedRequest?.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(transport.receivedRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["text"], "Hola")
        XCTAssertEqual(json["target_language"], "English")
        XCTAssertNil(json["model"])
    }

    func testThrowsForNonSuccessHTTPStatus() throws {
        let endpoint = URL(string: "https://translation.example.test/v1/translate")!
        let transport = StubHTTPTranslationTransport(
            data: Data(#"{"error":"unavailable"}"#.utf8),
            response: httpResponse(url: endpoint, statusCode: 503)
        )
        let provider = ScreenshotHTTPTranslationProvider(
            config: HTTPTranslationEndpointConfig(endpoint: endpoint),
            transport: transport
        )

        XCTAssertThrowsError(
            try provider.translate(ScreenshotTranslationRequest(sourceText: "Hello", targetLanguage: "fr"))
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                ScreenshotTranslationError.httpStatus(503).localizedDescription
            )
        }
    }

    func testThrowsForMissingTranslatedText() throws {
        let endpoint = URL(string: "https://translation.example.test/v1/translate")!
        let transport = StubHTTPTranslationTransport(
            data: Data(#"{"message":"ok"}"#.utf8),
            response: httpResponse(url: endpoint, statusCode: 200)
        )
        let provider = ScreenshotHTTPTranslationProvider(
            config: HTTPTranslationEndpointConfig(endpoint: endpoint),
            transport: transport
        )

        XCTAssertThrowsError(
            try provider.translate(ScreenshotTranslationRequest(sourceText: "Hello", targetLanguage: "fr"))
        ) { error in
            XCTAssertEqual(error as? ScreenshotTranslationError, .invalidResponse)
        }
    }

    func testThrowsInvalidResponseForMalformedOrWrongTypeResponseBody() throws {
        let endpoint = URL(string: "https://translation.example.test/v1/translate")!
        let invalidBodies = [
            Data("{".utf8),
            Data(#"{"translated_text":42}"#.utf8),
            Data()
        ]

        for body in invalidBodies {
            let transport = StubHTTPTranslationTransport(
                data: body,
                response: httpResponse(url: endpoint, statusCode: 200)
            )
            let provider = ScreenshotHTTPTranslationProvider(
                config: HTTPTranslationEndpointConfig(endpoint: endpoint),
                transport: transport
            )

            XCTAssertThrowsError(
                try provider.translate(ScreenshotTranslationRequest(sourceText: "Hello", targetLanguage: "fr"))
            ) { error in
                XCTAssertEqual(
                    error.localizedDescription,
                    "Screenshot translation response could not be decoded"
                )
            }
        }
    }

    func testWrapsTransportFailure() throws {
        let endpoint = URL(string: "https://translation.example.test/v1/translate")!
        let transport = StubHTTPTranslationTransport(error: StubTransportError())
        let provider = ScreenshotHTTPTranslationProvider(
            config: HTTPTranslationEndpointConfig(endpoint: endpoint),
            transport: transport
        )

        XCTAssertThrowsError(
            try provider.translate(ScreenshotTranslationRequest(sourceText: "Hello", targetLanguage: "fr"))
        ) { error in
            XCTAssertEqual(error as? ScreenshotTranslationError, .providerFailed("stub transport failed"))
        }
    }
}

private final class StubHTTPTranslationTransport: HTTPTranslationTransporting {
    private let result: Result<(Data, HTTPURLResponse), Error>
    private(set) var receivedRequest: URLRequest?

    init(data: Data, response: HTTPURLResponse) {
        self.result = .success((data, response))
    }

    init(error: Error) {
        self.result = .failure(error)
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        receivedRequest = request
        return try result.get()
    }
}

private struct StubTransportError: LocalizedError {
    var errorDescription: String? {
        "stub transport failed"
    }
}

private func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}
