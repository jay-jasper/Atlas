import Foundation

/// Top-level main-window tabs (⌘1-⌘5).
enum ShellTab: String, CaseIterable, Identifiable {
    case general
    case plugins
    case ai
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .plugins: return "插件"
        case .ai: return "AI"
        case .settings: return "设置"
        case .about: return "关于"
        }
    }

    var icon: String {
        switch self {
        case .general: return "square.grid.2x2"
        case .plugins: return "puzzlepiece.extension"
        case .ai: return "sparkles"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }

    var shortcutDigit: Int {
        switch self {
        case .general: return 1
        case .plugins: return 2
        case .ai: return 3
        case .settings: return 4
        case .about: return 5
        }
    }
}
