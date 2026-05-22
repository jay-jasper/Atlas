enum AtlasModule: String, CaseIterable, Identifiable {
    case aiLoadMonitor = "ai-load-monitor"
    case automation
    case monitoring
    case scratchpad
    case screenshot
    case skills
    case tokenbar
    case windowManager = "window-manager"

    var id: String { rawValue }

    var featureName: String {
        rawValue
    }

    var title: String {
        switch self {
        case .aiLoadMonitor:
            return "AI Load"
        case .automation:
            return "Automation"
        case .monitoring:
            return "Monitoring"
        case .scratchpad:
            return "Scratchpad"
        case .screenshot:
            return "Screenshot"
        case .skills:
            return "AI Skills"
        case .tokenbar:
            return "TokenBar"
        case .windowManager:
            return "Window Manager"
        }
    }
}
