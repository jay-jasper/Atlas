import Foundation

/// 应用语言(先支持中/英)。启动时解析一次;切换后需重启生效。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zh
    case en

    static let storageKey = "atlas.language"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return loc("跟随系统", "System")
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }

    /// Resolved once per process so hardcoded strings stay consistent for the
    /// whole session; changing the setting prompts a relaunch.
    static let current: AppLanguage = {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        let stored = AppLanguage(rawValue: raw) ?? .system
        guard stored == .system else { return stored }
        let preferred = Locale.preferredLanguages.first ?? "zh"
        return preferred.hasPrefix("zh") ? .zh : .en
    }()
}

/// 轻量双语文案:`loc("中文", "English")`。
func loc(_ zh: String, _ en: String) -> String {
    AppLanguage.current == .en ? en : zh
}
