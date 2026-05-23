enum AtlasModule: String, CaseIterable, Identifiable {
    case aiLoadMonitor = "ai-load-monitor"
    case audioHub = "audio-hub"
    case automation
    case clipboard
    case flowInbox = "flow-inbox"
    case monitoring
    case privacy
    case sceneSystem = "scene-system"
    case scratchpad
    case screenshot
    case skills
    case systemUtilities = "system-utilities"
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
        case .audioHub:
            return "Audio Hub"
        case .automation:
            return "Automation"
        case .clipboard:
            return "Clipboard History"
        case .flowInbox:
            return "Flow Inbox"
        case .monitoring:
            return "Monitoring"
        case .privacy:
            return "Privacy Pulse"
        case .sceneSystem:
            return "Scene System"
        case .scratchpad:
            return "Scratchpad"
        case .screenshot:
            return "Screenshot"
        case .skills:
            return "AI Skills"
        case .systemUtilities:
            return "System Utilities"
        case .tokenbar:
            return "TokenBar"
        case .windowManager:
            return "Window Manager"
        }
    }
}
