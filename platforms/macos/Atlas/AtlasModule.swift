enum AtlasModule: String, CaseIterable, Identifiable {
    case aiLoadMonitor = "ai-load-monitor"
    case appAudio = "app-audio"
    case audioHub = "audio-hub"
    case automation
    case calendar
    case clipboard
    case colorPicker = "color-picker"
    case ddcControl = "ddc-control"
    case flowInbox = "flow-inbox"
    case fnKey = "fn-key"
    case monitoring
    case networkMonitor = "network-monitor"
    case privacy
    case sceneSystem = "scene-system"
    case scratchpad
    case screenshot
    case skills
    case systemUtilities = "system-utilities"
    case tokenbar
    case totp
    case windowManager = "window-manager"

    var id: String { rawValue }

    var featureName: String {
        rawValue
    }

    var title: String {
        switch self {
        case .aiLoadMonitor:
            return "AI Load"
        case .appAudio:
            return "App Audio"
        case .audioHub:
            return "Audio Hub"
        case .automation:
            return "Automation"
        case .calendar:
            return "Calendar"
        case .clipboard:
            return "Clipboard History"
        case .colorPicker:
            return "Color Picker"
        case .ddcControl:
            return "DDC Monitor Control"
        case .flowInbox:
            return "Flow Inbox"
        case .fnKey:
            return "Fn Key Switcher"
        case .monitoring:
            return "Monitoring"
        case .networkMonitor:
            return "Network Monitor"
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
        case .totp:
            return "TOTP 2FA"
        case .windowManager:
            return "Window Manager"
        }
    }
}
