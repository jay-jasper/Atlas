import Foundation

/// 翻译:AI 引擎复用。语言对可配;源=自动检测,
/// 中文输入自动切换英文目标(Raycast 式智能换向)。
@MainActor
final class TranslateService: ObservableObject {
    static let shared = TranslateService()

    @Published var targetLanguage: String {
        didSet { UserDefaults.standard.set(targetLanguage, forKey: "translate.target") }
    }
    @Published var secondaryLanguage: String {
        didSet { UserDefaults.standard.set(secondaryLanguage, forKey: "translate.secondary") }
    }

    let runner = AiOneShotRunner()

    nonisolated static let languages: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"),
        ("ja", "日本語"), ("ko", "한국어"), ("fr", "Français"), ("de", "Deutsch"),
        ("es", "Español"), ("pt", "Português"), ("ru", "Русский"), ("it", "Italiano"),
    ]

    init() {
        targetLanguage = UserDefaults.standard.string(forKey: "translate.target") ?? "zh-Hans"
        secondaryLanguage = UserDefaults.standard.string(forKey: "translate.secondary") ?? "en"
    }

    /// 输入已是目标语言 → 用次目标(中→英自动换向)。
    func effectiveTarget(for text: String) -> String {
        let containsCJK = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let targetIsChinese = targetLanguage.hasPrefix("zh")
        if containsCJK, targetIsChinese { return secondaryLanguage }
        return targetLanguage
    }

    nonisolated static func prompt(text: String, target: String) -> String {
        let name = languages.first(where: { $0.code == target })?.name ?? target
        return "Translate the following text into \(name) (\(target)). Output ONLY the translation, no explanations:\n\n\(text)"
    }

    func translate(_ text: String, onDone: ((String) -> Void)? = nil) {
        let target = effectiveTarget(for: text)
        runner.run(prompt: Self.prompt(text: text, target: target), onDone: onDone)
    }
}
