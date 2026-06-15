import AppKit
import Foundation

@MainActor
final class TranslationPopupService: ObservableObject {
    @Published var sourceText: String = ""
    @Published var targetLanguage: String = "en"
    @Published private(set) var translatedText: String = ""
    @Published private(set) var statusMessage: String = ""

    /// Common target languages offered in the UI.
    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("zh", "Chinese"), ("ja", "Japanese"),
        ("ko", "Korean"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
    ]

    private let translator: ScreenshotTranslating
    private let readPasteboard: () -> String?

    init(
        translator: ScreenshotTranslating = LocalPlaceholderScreenshotTranslationService(),
        readPasteboard: @escaping () -> String? = { NSPasteboard.general.string(forType: .string) }
    ) {
        self.translator = translator
        self.readPasteboard = readPasteboard
    }

    /// Translates the current `sourceText`.
    func translate() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { translatedText = ""; return }
        do {
            let result = try translator.translate(text, targetLanguage: targetLanguage)
            translatedText = result.translatedText
            statusMessage = ""
        } catch {
            statusMessage = "Translation failed."
            translatedText = ""
        }
    }

    /// Loads the current clipboard selection and translates it.
    func translateSelection() {
        guard let clip = readPasteboard(), !clip.isEmpty else {
            statusMessage = "Copy text first, then translate."
            return
        }
        sourceText = clip
        translate()
    }

    func copyResult() {
        guard !translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
    }
}
