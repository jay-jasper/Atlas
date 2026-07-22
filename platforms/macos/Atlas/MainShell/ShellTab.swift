import Foundation

/// Top-level main-window tabs (⌘1-⌘4).
enum ShellTab: String, CaseIterable, Identifiable {
    case general
    case plugins
    case ai
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return loc("通用", "General")
        case .plugins: return loc("插件", "Plugins")
        case .ai: return "AI"
        case .about: return loc("关于", "About")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .plugins: return "puzzlepiece.extension"
        case .ai: return "sparkles"
        case .about: return "info.circle"
        }
    }

    var shortcutDigit: Int {
        switch self {
        case .general: return 1
        case .plugins: return 2
        case .ai: return 3
        case .about: return 4
        }
    }
}
