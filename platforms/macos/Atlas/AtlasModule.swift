enum AtlasModule: String, CaseIterable, Identifiable {
    case automation
    case monitoring
    case screenshot
    case windowManager = "window-manager"

    var id: String { rawValue }

    var featureName: String {
        rawValue
    }

    var title: String {
        switch self {
        case .automation:
            return "Automation"
        case .monitoring:
            return "Monitoring"
        case .screenshot:
            return "Screenshot"
        case .windowManager:
            return "Window Manager"
        }
    }
}
