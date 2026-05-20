import Foundation

struct ScreenshotTranslationResult: Equatable {
    let sourceText: String
    let translatedText: String
    let targetLanguage: String
}

protocol ScreenshotTranslating {
    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult
}

enum ScreenshotTranslationError: LocalizedError {
    case emptyText
    case unsupportedLocalTranslation

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Screenshot text is empty and cannot be translated"
        case .unsupportedLocalTranslation:
            return "Local screenshot translation is not supported yet"
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
