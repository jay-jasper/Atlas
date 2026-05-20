import Foundation

struct ScreenshotTranslationResult: Equatable {
    let sourceText: String
    let translatedText: String
    let targetLanguage: String
}

struct ScreenshotTranslationRequest: Equatable {
    let sourceText: String
    let targetLanguage: String
}

protocol ScreenshotTranslationProviding {
    func translate(_ request: ScreenshotTranslationRequest) throws -> ScreenshotTranslationResult
}

protocol ScreenshotTranslating {
    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult
}

enum ScreenshotTranslationError: LocalizedError, Equatable {
    case emptyText
    case unsupportedLocalTranslation
    case missingEndpoint
    case invalidResponse
    case httpStatus(Int)
    case providerFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Screenshot text is empty and cannot be translated"
        case .unsupportedLocalTranslation:
            return "Local screenshot translation is not supported yet"
        case .missingEndpoint:
            return "Screenshot translation endpoint is not configured"
        case .invalidResponse:
            return "Screenshot translation response could not be decoded"
        case .httpStatus(let statusCode):
            return "Screenshot translation request failed with HTTP \(statusCode)"
        case .providerFailed(let message):
            return "Screenshot translation failed: \(message)"
        }
    }
}

struct LocalPlaceholderScreenshotTranslationService: ScreenshotTranslating {
    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScreenshotTranslationError.emptyText
        }

        throw ScreenshotTranslationError.unsupportedLocalTranslation
    }
}

struct ProviderBackedScreenshotTranslationService: ScreenshotTranslating {
    let provider: ScreenshotTranslationProviding

    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ScreenshotTranslationError.emptyText
        }

        return try provider.translate(
            ScreenshotTranslationRequest(
                sourceText: trimmedText,
                targetLanguage: targetLanguage
            )
        )
    }
}
