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

/// Small offline translation baseline used when no provider is configured. It
/// handles common OCR/UI vocabulary without network access and preserves words
/// it does not know, so local mode always produces a usable result.
struct LocalDictionaryScreenshotTranslationService: ScreenshotTranslating {
    private static let languageAliases: [String: String] = [
        "fr": "fr", "french": "fr", "français": "fr",
        "es": "es", "spanish": "es", "español": "es",
        "de": "de", "german": "de", "deutsch": "de",
        "zh": "zh", "chinese": "zh", "中文": "zh",
        "en": "en", "english": "en",
    ]

    private static let dictionaries: [String: [String: String]] = [
        "fr": ["hello": "bonjour", "world": "monde", "yes": "oui", "no": "non", "save": "enregistrer", "cancel": "annuler", "open": "ouvrir", "close": "fermer", "settings": "réglages"],
        "es": ["hello": "hola", "world": "mundo", "yes": "sí", "no": "no", "save": "guardar", "cancel": "cancelar", "open": "abrir", "close": "cerrar", "settings": "ajustes"],
        "de": ["hello": "hallo", "world": "welt", "yes": "ja", "no": "nein", "save": "speichern", "cancel": "abbrechen", "open": "öffnen", "close": "schließen", "settings": "einstellungen"],
        "zh": ["hello": "你好", "world": "世界", "yes": "是", "no": "否", "save": "保存", "cancel": "取消", "open": "打开", "close": "关闭", "settings": "设置"],
        "en": [:],
    ]

    func translate(_ text: String, targetLanguage: String) throws -> ScreenshotTranslationResult {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw ScreenshotTranslationError.emptyText }
        let requested = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let language = Self.languageAliases[requested],
              let dictionary = Self.dictionaries[language] else {
            throw ScreenshotTranslationError.providerFailed("Unsupported local language: \(targetLanguage)")
        }
        let translated = source
            .components(separatedBy: .whitespaces)
            .map { token in Self.translateToken(token, with: dictionary) }
            .joined(separator: " ")
        return ScreenshotTranslationResult(
            sourceText: source,
            translatedText: translated,
            targetLanguage: targetLanguage
        )
    }

    private static func translateToken(_ token: String, with dictionary: [String: String]) -> String {
        let letters = token.trimmingCharacters(in: .punctuationCharacters)
        guard let replacement = dictionary[letters.lowercased()] else { return token }
        return token.replacingOccurrences(of: letters, with: replacement)
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
