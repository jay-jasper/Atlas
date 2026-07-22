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
        case .general: return "通用"
        case .plugins: return "插件"
        case .ai: return "AI"
        case .about: return "关于"
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
