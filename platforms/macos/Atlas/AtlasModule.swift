enum AtlasModule: String, CaseIterable, Identifiable {
    case aiLoadMonitor = "ai-load-monitor"
    case automation
    case monitoring
    case screenshot
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
        case .screenshot:
            return "Screenshot"
        case .tokenbar:
            return "TokenBar"
        case .windowManager:
            return "Window Manager"
        }
    }
}
