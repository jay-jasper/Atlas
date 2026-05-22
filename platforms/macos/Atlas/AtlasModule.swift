enum AtlasModule: String, CaseIterable, Identifiable {
    case automation
    case screenshot
    case monitoring

    var id: String { rawValue }

    var featureName: String {
        switch self {
        case .automation:
            return "automation"
        case .screenshot:
            return "screenshot"
        case .monitoring:
            return "monitoring"
        }
    }

    var title: String {
        switch self {
        case .automation:
            return "Automation"
        case .screenshot:
            return "Screenshot"
        case .monitoring:
            return "Monitoring"
        }
    }
}
