enum AtlasModule: String, CaseIterable, Identifiable {
    case aiLoadMonitor = "ai-load-monitor"
    case altTab = "alt-tab"
    case appAudio = "app-audio"
    case appCleaner = "app-cleaner"
    case aspectGuide = "aspect-guide"
    case audioHub = "audio-hub"
    case audioMeter = "audio-meter"
    case audioRecording = "audio-recording"
    case automation
    case batteryHealth = "battery-health"
    case bluetoothBattery = "bluetooth-battery"
    case browserRouter = "browser-router"
    case calendar
    case chapterMarker = "chapter-marker"
    case clipboard
    case colorPicker = "color-picker"
    case colorSampler = "color-sampler"
    case ddcControl = "ddc-control"
    case diskUsage = "disk-usage"
    case dragShelf = "drag-shelf"
    case envManager = "env-manager"
    case flowInbox = "flow-inbox"
    case fnKey = "fn-key"
    case gifProcessing = "gif-processing"
    case hosts
    case keyboardDisplay = "keyboard-display"
    case keyboardSounds = "keyboard-sounds"
    case lanTransfer = "lan-transfer"
    case monitoring
    case networkMonitor = "network-monitor"
    case noiseGate = "noise-gate"
    case nowPlaying = "now-playing"
    case obsControl = "obs-control"
    case packetMonitor = "packet-monitor"
    case pomodoro
    case privacy
    case proxy
    case quickSwitches = "quick-switches"
    case recordingIndicator = "recording-indicator"
    case rss
    case sceneSystem = "scene-system"
    case scratchpad
    case screenshot
    case scrollSmoothing = "scroll-smoothing"
    case skills
    case soundFeedback = "sound-feedback"
    case subtitles
    case systemUtilities = "system-utilities"
    case teleprompter
    case textExpansion = "text-expansion"
    case tokenbar
    case totp
    case translation
    case watermark
    case webWallpaper = "web-wallpaper"
    case windowManager = "window-manager"

    var id: String { rawValue }

    var featureName: String {
        rawValue
    }

    var title: String {
        switch self {
        case .aiLoadMonitor:
            return "AI Load"
        case .altTab:
            return "Window Switcher"
        case .appAudio:
            return "App Audio"
        case .appCleaner:
            return "App Cleaner"
        case .aspectGuide:
            return "Aspect Ratio Guide"
        case .audioHub:
            return "Audio Hub"
        case .audioMeter:
            return "Audio Level Meter"
        case .audioRecording:
            return "Audio Recording"
        case .automation:
            return "Automation"
        case .batteryHealth:
            return "Battery Health"
        case .bluetoothBattery:
            return "Bluetooth Battery"
        case .browserRouter:
            return "Browser Router"
        case .calendar:
            return "Calendar"
        case .chapterMarker:
            return "Chapter Markers"
        case .clipboard:
            return "Clipboard History"
        case .colorPicker:
            return "Color Picker"
        case .colorSampler:
            return "Color Sampler"
        case .ddcControl:
            return "DDC Monitor Control"
        case .diskUsage:
            return "Disk Usage"
        case .dragShelf:
            return "Drag Shelf"
        case .envManager:
            return "Env Variables"
        case .flowInbox:
            return "Flow Inbox"
        case .fnKey:
            return "Fn Key Switcher"
        case .gifProcessing:
            return "GIF Post-Processing"
        case .hosts:
            return "Hosts Editor"
        case .keyboardDisplay:
            return "Keyboard Display"
        case .keyboardSounds:
            return "Keyboard Sounds"
        case .lanTransfer:
            return "LAN Transfer"
        case .monitoring:
            return "Monitoring"
        case .networkMonitor:
            return "Network Monitor"
        case .noiseGate:
            return "Mic Noise Gate"
        case .nowPlaying:
            return "Now Playing"
        case .obsControl:
            return "OBS Control"
        case .packetMonitor:
            return "Packet Monitor"
        case .pomodoro:
            return "Pomodoro"
        case .privacy:
            return "Privacy Pulse"
        case .proxy:
            return "Proxy Switcher"
        case .quickSwitches:
            return "Quick Switches"
        case .recordingIndicator:
            return "Recording Indicator"
        case .rss:
            return "RSS Reader"
        case .sceneSystem:
            return "Scene System"
        case .scratchpad:
            return "Scratchpad"
        case .screenshot:
            return "Screenshot"
        case .scrollSmoothing:
            return "Scroll Smoothing"
        case .skills:
            return "AI Skills"
        case .soundFeedback:
            return "Sound Feedback"
        case .subtitles:
            return "Subtitle Tools"
        case .systemUtilities:
            return "System Utilities"
        case .teleprompter:
            return "Teleprompter"
        case .textExpansion:
            return "Text Expansion"
        case .tokenbar:
            return "TokenBar"
        case .totp:
            return "TOTP 2FA"
        case .translation:
            return "Translation"
        case .watermark:
            return "Watermark"
        case .webWallpaper:
            return "Web Wallpaper"
        case .windowManager:
            return "Window Manager"
        }
    }
}
