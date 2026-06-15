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
    case hosts
    case monitoring
    case networkMonitor = "network-monitor"
    case pomodoro
    case privacy
    case sceneSystem = "scene-system"
    case scratchpad
    case screenshot
    case skills
    case subtitles
    case systemUtilities = "system-utilities"
    case textExpansion = "text-expansion"
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
        case .hosts:
            return "Hosts Editor"
        case .monitoring:
            return "Monitoring"
        case .networkMonitor:
            return "Network Monitor"
        case .pomodoro:
            return "Pomodoro"
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
        case .subtitles:
            return "Subtitle Tools"
        case .systemUtilities:
            return "System Utilities"
        case .textExpansion:
            return "Text Expansion"
        case .tokenbar:
            return "TokenBar"
        case .totp:
            return "TOTP 2FA"
        case .windowManager:
            return "Window Manager"
        }
    }
}
