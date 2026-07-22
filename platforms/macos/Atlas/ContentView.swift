import IOKit.ps
import Network
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class SceneNetworkStatusService: ObservableObject {
    @Published private(set) var triggerTokens: [String] = []

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "ai.atlas.scene.network-monitor")
    private var isRunning = false

    func start() {
        guard isRunning == false else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let tokens = Self.tokens(for: path)
            DispatchQueue.main.async {
                self?.triggerTokens = tokens
            }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        monitor?.cancel()
        monitor = nil
        triggerTokens = []
        isRunning = false
    }

    deinit {
        if isRunning {
            monitor?.cancel()
        }
    }

    nonisolated private static func tokens(for path: NWPath) -> [String] {
        var tokens: [String] = path.status == .satisfied ? ["online"] : ["offline"]
        let interfaces = path.availableInterfaces
        tokens.append(contentsOf: interfaces.map(\.name))
        tokens.append(contentsOf: interfaces.map { interfaceTypeTitle($0.type) })
        if interfaces.count > 1 {
            tokens.append("multi-homed")
        }
        return Array(Set(tokens)).sorted()
    }

    nonisolated private static func interfaceTypeTitle(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi:
            return "wifi"
        case .wiredEthernet:
            return "ethernet"
        case .cellular:
            return "cellular"
        case .loopback:
            return "loopback"
        case .other:
            return "other"
        @unknown default:
            return "unknown"
        }
    }
}

private enum CaptureStatusKind {
    case success
    case error
}

private enum PrimaryPanelSection: Hashable, CaseIterable {
    case sceneCenter
    case audioHub
    case flowInbox
    case screenshot
    case monitoring
    case clipboard
    case privacy
    case aiLoad
    case scratchpad
    case systemUtilities
    case tokenBar
    case windowManager
    case colorPicker
    case ddcControl
    case calendar
    case networkMonitor
    case appAudio
    case fnKey
    case totp
    case pomodoro
    case subtitles
    case textExpansion
    case hosts
    case browserRouter
    case envManager
    case diskUsage
    case proxy
    case rss
    case quickSwitches
    case chapterMarker
    case appCleaner
    case aspectGuide
    case dragShelf
    case batteryHealth
    case watermark
    case obsControl
    case teleprompter
    case webWallpaper
    case keyboardDisplay
    case scrollSmoothing
    case gifProcessing
    case altTab
    case colorSampler
    case recordingIndicator
    case soundFeedback
    case keyboardSounds
    case audioMeter
    case audioRecording
    case lanTransfer
    case translation
    case bluetoothBattery
    case noiseGate
    case packetMonitor
    case nowPlaying
    case liveCaption
    case plugins
    case notch
    case transcription
    case recordingEditor
    case scripting
}


/// Press feedback shared by shell buttons: scale to 0.98 and tighten shadow.
private struct GlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.05 : 0.12), radius: configuration.isPressed ? 3 : 8, y: configuration.isPressed ? 1 : 3)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ShellTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? AnyShapeStyle(.ultraThinMaterial)
                        : AnyShapeStyle(Color.white.opacity(isHovered ? 0.10 : 0)),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            Color.white.opacity(isSelected ? 0.45 : (isHovered ? 0.25 : 0)),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.75))
        }
        .buttonStyle(GlassPressButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Fine-grained sidebar groups for the main window shell (first level of the
/// two-level sidebar). Ordered arrays double as the tool order inside a group.
private enum ShellToolGroup: String, CaseIterable, Identifiable {
    case captureRecording
    case audio
    case speech
    case systemMonitor
    case hardware
    case inputFeedback
    case systemTools
    case windowing
    case productivity
    case color
    case network
    case extensions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureRecording: return "截图录制"
        case .audio: return "音频"
        case .speech: return "字幕转写"
        case .systemMonitor: return "系统监控"
        case .hardware: return "硬件设备"
        case .inputFeedback: return "键盘反馈"
        case .systemTools: return "系统工具"
        case .windowing: return "窗口管理"
        case .productivity: return "效率"
        case .color: return "颜色"
        case .network: return "网络"
        case .extensions: return "扩展"
        }
    }

    var icon: String {
        switch self {
        case .captureRecording: return "camera.viewfinder"
        case .audio: return "waveform"
        case .speech: return "captions.bubble"
        case .systemMonitor: return "gauge"
        case .hardware: return "cpu"
        case .inputFeedback: return "keyboard"
        case .systemTools: return "wrench.and.screwdriver"
        case .windowing: return "macwindow.on.rectangle"
        case .productivity: return "square.and.pencil"
        case .color: return "paintpalette"
        case .network: return "network"
        case .extensions: return "puzzlepiece.extension"
        }
    }

    var sections: [PrimaryPanelSection] {
        switch self {
        case .captureRecording:
            return [
                .screenshot, .gifProcessing, .watermark, .recordingIndicator,
                .recordingEditor, .obsControl, .teleprompter, .chapterMarker,
            ]
        case .audio:
            return [.audioHub, .appAudio, .audioMeter, .audioRecording, .noiseGate, .nowPlaying]
        case .speech:
            return [.subtitles, .transcription, .liveCaption, .translation]
        case .systemMonitor:
            return [.sceneCenter, .monitoring, .aiLoad, .tokenBar, .privacy, .systemUtilities]
        case .hardware:
            return [.batteryHealth, .bluetoothBattery, .ddcControl, .diskUsage]
        case .inputFeedback:
            return [.fnKey, .keyboardDisplay, .keyboardSounds, .soundFeedback]
        case .systemTools:
            return [.envManager, .hosts, .appCleaner]
        case .windowing:
            return [
                .windowManager, .altTab, .quickSwitches, .aspectGuide, .notch,
                .scrollSmoothing, .webWallpaper, .dragShelf,
            ]
        case .productivity:
            return [
                .flowInbox, .clipboard, .scratchpad, .textExpansion, .totp,
                .pomodoro, .calendar, .rss,
            ]
        case .color:
            return [.colorPicker, .colorSampler]
        case .network:
            return [.networkMonitor, .packetMonitor, .proxy, .browserRouter, .lanTransfer]
        case .extensions:
            return [.plugins, .scripting]
        }
    }

    static func group(containing section: PrimaryPanelSection) -> ShellToolGroup {
        allCases.first { $0.sections.contains(section) } ?? .captureRecording
    }
}

/// Top tab bar entries for the currently selected tool: its live panel plus
/// its settings pages.
private enum ShellToolTab: Hashable {
    case overview
    case library
    case settings
    case translation

    var title: String {
        switch self {
        case .overview: return "功能"
        case .library: return "截图库"
        case .settings: return "设置"
        case .translation: return "翻译"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "slider.horizontal.3"
        case .library: return "photo.stack"
        case .settings: return "gearshape"
        case .translation: return "character.bubble"
        }
    }
}

/// Per-tool shell preferences persisted in UserDefaults (favorites and
/// menu-bar-panel visibility), keyed by feature name.
private enum ShellToolPrefs {
    private static let favoritesKey = "atlas.shell.favorites"
    private static let hiddenInPopoverKey = "atlas.shell.hiddenInPopover"
    private static let dashboardKey = "atlas.shell.dashboard"

    /// Starter set for first launch: the everyday tools.
    private static let defaultDashboard = ["screenshot", "clipboard", "monitoring", "color-picker"]

    static func loadDashboard() -> [String] {
        UserDefaults.standard.stringArray(forKey: dashboardKey) ?? defaultDashboard
    }

    static func saveDashboard(_ values: [String]) {
        UserDefaults.standard.set(values, forKey: dashboardKey)
    }

    static func loadFavorites() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
    }

    static func saveFavorites(_ values: Set<String>) {
        UserDefaults.standard.set(Array(values).sorted(), forKey: favoritesKey)
    }

    static func loadHiddenInPopover() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenInPopoverKey) ?? [])
    }

    static func saveHiddenInPopover(_ values: Set<String>) {
        UserDefaults.standard.set(Array(values).sorted(), forKey: hiddenInPopoverKey)
    }
}

extension AtlasModule {
    /// Chinese display title for the main window shell (the module's `title`
    /// stays English for existing panels/tests).
    fileprivate var localizedTitle: String {
        switch self {
        case .aiLoadMonitor: return "AI 负载"
        case .altTab: return "窗口切换器"
        case .appAudio: return "应用音频"
        case .appCleaner: return "应用清理"
        case .aspectGuide: return "宽高比参考线"
        case .audioHub: return "音频中心"
        case .audioMeter: return "音量电平表"
        case .audioRecording: return "录音"
        case .automation: return "自动化"
        case .batteryHealth: return "电池健康"
        case .bluetoothBattery: return "蓝牙电量"
        case .browserRouter: return "浏览器分流"
        case .calendar: return "日历"
        case .chapterMarker: return "章节标记"
        case .clipboard: return "剪贴板历史"
        case .colorPicker: return "取色器"
        case .colorSampler: return "颜色采样"
        case .ddcControl: return "DDC 显示器控制"
        case .diskUsage: return "磁盘用量"
        case .dragShelf: return "拖拽暂存架"
        case .envManager: return "环境变量"
        case .flowInbox: return "流转收件箱"
        case .fnKey: return "Fn 键切换"
        case .gifProcessing: return "GIF 后处理"
        case .hosts: return "Hosts 编辑器"
        case .keyboardDisplay: return "按键显示"
        case .keyboardSounds: return "键盘音效"
        case .lanTransfer: return "局域网传输"
        case .liveCaption: return "实时字幕"
        case .monitoring: return "系统监控"
        case .networkMonitor: return "网络监控"
        case .noiseGate: return "麦克风噪声门"
        case .notch: return "刘海岛"
        case .nowPlaying: return "正在播放"
        case .obsControl: return "OBS 控制"
        case .packetMonitor: return "抓包监控"
        case .plugins: return "插件"
        case .pomodoro: return "番茄钟"
        case .privacy: return "隐私监测"
        case .proxy: return "代理切换"
        case .quickSwitches: return "快捷开关"
        case .recordingEditor: return "录制剪辑"
        case .recordingIndicator: return "录制指示器"
        case .rss: return "RSS 阅读器"
        case .sceneSystem: return "场景系统"
        case .scratchpad: return "速记板"
        case .screenshot: return "截图"
        case .scripting: return "脚本"
        case .scrollSmoothing: return "平滑滚动"
        case .skills: return "AI 技能"
        case .soundFeedback: return "声音反馈"
        case .subtitles: return "字幕工具"
        case .systemUtilities: return "系统实用工具"
        case .teleprompter: return "提词器"
        case .textExpansion: return "文本扩展"
        case .tokenbar: return "TokenBar"
        case .totp: return "TOTP 两步验证"
        case .transcription: return "转写"
        case .translation: return "翻译"
        case .watermark: return "水印"
        case .webWallpaper: return "网页壁纸"
        case .windowManager: return "窗口管理"
        }
    }
}

/// Main window pages: dashboard (card grid of the user's tools), the full
/// tool library (browse/add), and a single tool's detail.
private enum ShellPage: Hashable {
    case dashboard
    case library
    case tool
}

extension PrimaryPanelSection {
    fileprivate static func section(forFeatureName name: String) -> PrimaryPanelSection? {
        allCases.first { $0.module.featureName == name }
    }

    /// Top tabs available for this tool.
    fileprivate var tabs: [ShellToolTab] {
        switch self {
        case .screenshot:
            return [.overview, .library, .settings, .translation]
        case .translation:
            return [.overview, .settings]
        default:
            return [.overview, .settings]
        }
    }

    /// 1:1 module behind each panel section (title, feature name, availability).
    fileprivate var module: AtlasModule {
        switch self {
        case .sceneCenter: return .sceneSystem
        case .audioHub: return .audioHub
        case .flowInbox: return .flowInbox
        case .screenshot: return .screenshot
        case .monitoring: return .monitoring
        case .clipboard: return .clipboard
        case .privacy: return .privacy
        case .aiLoad: return .aiLoadMonitor
        case .scratchpad: return .scratchpad
        case .systemUtilities: return .systemUtilities
        case .tokenBar: return .tokenbar
        case .windowManager: return .windowManager
        case .colorPicker: return .colorPicker
        case .ddcControl: return .ddcControl
        case .calendar: return .calendar
        case .networkMonitor: return .networkMonitor
        case .appAudio: return .appAudio
        case .fnKey: return .fnKey
        case .totp: return .totp
        case .pomodoro: return .pomodoro
        case .subtitles: return .subtitles
        case .textExpansion: return .textExpansion
        case .hosts: return .hosts
        case .browserRouter: return .browserRouter
        case .envManager: return .envManager
        case .diskUsage: return .diskUsage
        case .proxy: return .proxy
        case .rss: return .rss
        case .quickSwitches: return .quickSwitches
        case .chapterMarker: return .chapterMarker
        case .appCleaner: return .appCleaner
        case .aspectGuide: return .aspectGuide
        case .dragShelf: return .dragShelf
        case .batteryHealth: return .batteryHealth
        case .watermark: return .watermark
        case .obsControl: return .obsControl
        case .teleprompter: return .teleprompter
        case .webWallpaper: return .webWallpaper
        case .keyboardDisplay: return .keyboardDisplay
        case .scrollSmoothing: return .scrollSmoothing
        case .gifProcessing: return .gifProcessing
        case .altTab: return .altTab
        case .colorSampler: return .colorSampler
        case .recordingIndicator: return .recordingIndicator
        case .soundFeedback: return .soundFeedback
        case .keyboardSounds: return .keyboardSounds
        case .audioMeter: return .audioMeter
        case .audioRecording: return .audioRecording
        case .lanTransfer: return .lanTransfer
        case .translation: return .translation
        case .bluetoothBattery: return .bluetoothBattery
        case .noiseGate: return .noiseGate
        case .packetMonitor: return .packetMonitor
        case .nowPlaying: return .nowPlaying
        case .liveCaption: return .liveCaption
        case .plugins: return .plugins
        case .notch: return .notch
        case .transcription: return .transcription
        case .recordingEditor: return .recordingEditor
        case .scripting: return .scripting
        }
    }
}

private struct AudioHubSceneModule: SceneControllableModule {
    let isEnabled: Bool
    let service: AudioHubService?

    let moduleID: SceneModuleID = .audioHub
    let isSceneControllable = true
    let configurableSettings = ["default output", "default input", "panel order", "visibility"]
    let supportedActions = ["apply-audio-preset"]

    func capabilitySnapshot() -> SceneModuleCapabilitySnapshot {
        SceneModuleCapabilitySnapshot(
            moduleID: moduleID,
            isAvailable: isEnabled && service != nil,
            stateSummary: service?.statusMessage ?? "Audio Hub unavailable",
            configurableSettings: configurableSettings,
            supportedActions: supportedActions
        )
    }
}

private struct FlowInboxSceneModule: SceneControllableModule {
    let isEnabled: Bool

    let moduleID: SceneModuleID = .flowInbox
    let isSceneControllable = true
    let configurableSettings = ["panel order", "visibility", "favorites preference"]
    let supportedActions = ["save-note"]

    func capabilitySnapshot() -> SceneModuleCapabilitySnapshot {
        SceneModuleCapabilitySnapshot(
            moduleID: moduleID,
            isAvailable: isEnabled,
            stateSummary: isEnabled ? "Flow Inbox is available for recent content and Quick File Send" : "Flow Inbox is unavailable",
            configurableSettings: configurableSettings,
            supportedActions: supportedActions
        )
    }
}

private struct SystemUtilitiesSceneModule: SceneControllableModule {
    let isEnabled: Bool
    let keepAwakeStatus: SystemUtilityStatus
    let presentationStatus: SystemUtilityStatus

    let moduleID: SceneModuleID = .systemUtilities
    let isSceneControllable = true
    let configurableSettings = ["panel order", "visibility"]
    let supportedActions = ["toggle-keep-awake", "toggle-presentation-mode", "open-hand-mirror", "refresh-displays"]

    func capabilitySnapshot() -> SceneModuleCapabilitySnapshot {
        SceneModuleCapabilitySnapshot(
            moduleID: moduleID,
            isAvailable: isEnabled,
            stateSummary: "Keep Awake: \(statusSummary(for: keepAwakeStatus)) • Presentation: \(statusSummary(for: presentationStatus))",
            configurableSettings: configurableSettings,
            supportedActions: supportedActions
        )
    }

    private func statusSummary(for status: SystemUtilityStatus) -> String {
        switch status {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case .unavailable(let detail), .failed(let detail):
            return detail
        }
    }
}

private struct ScratchpadSceneModule: SceneControllableModule {
    let isEnabled: Bool

    let moduleID: SceneModuleID = .scratchpad
    let isSceneControllable = true
    let configurableSettings = ["panel order", "visibility"]
    let supportedActions = ["save-note"]

    func capabilitySnapshot() -> SceneModuleCapabilitySnapshot {
        SceneModuleCapabilitySnapshot(
            moduleID: moduleID,
            isAvailable: isEnabled,
            stateSummary: isEnabled ? "Scratchpad storage is available" : "Scratchpad is unavailable",
            configurableSettings: configurableSettings,
            supportedActions: supportedActions
        )
    }
}

struct ContentView: View {
    @State private var statusText: String = "正在初始化…"
    @State private var features: [AtlasFeature] = []
    @State private var enabledFeatures: [String: Bool] = [:]
    @State private var snapshot: MonitoringSystemSnapshot? = nil
    @State private var capturedScreenshot: CapturedScreenshot?
    @State private var recognizedScreenshotText: String = ""
    @State private var isRecognizingScreenshotText: Bool = false
    @State private var translatedScreenshotText: String = ""
    @State private var isTranslatingScreenshotText: Bool = false
    @State private var screenshotLibraryItems: [ScreenshotLibraryItem] = []
    @State private var screenshotLibraryQuery: String = ""
    @State private var clipboardHistoryItems: [ClipboardHistoryItem] = []
    @State private var clipboardHistoryQuery: String = ""
    @State private var activeLibraryItemID: UUID?
    @State private var screenshotFeatureSettings: ScreenshotFeatureSettings = .defaultEnabled
    @State private var translationSettingsDraft: ScreenshotTranslationSettingsDraft = .empty
    @State private var isTranslationConfigured: Bool = false
    @State private var screenshotTextRevision: Int = 0
    @State private var screenshotOCRRevision: Int = 0
    @State private var screenshotTranslationRevision: Int = 0
    @State private var captureStatus: String = ""
    @State private var captureStatusKind: CaptureStatusKind = .success
    @State private var showCaptureStatus: Bool = false
    @State private var statusHideToken: Int = 0
    @State private var annotatedScreenshotData: Data?
    @State private var isRecordingGIF = false
    @State private var lastGIFOutput: ScreenshotGIFOutputItem?
    @State private var gifRecordingSession: ScreenshotGIFRecordingSession?
    @State private var cpuHistory: [Double] = []
    @State private var memoryHistory: [Double] = []
    @State private var tokenBarSummary: TokenBarSummary = .empty
    @State private var localAILoadSnapshot: LocalAILoadSnapshot = .empty
    @State private var privacyPulseSnapshot = PrivacyPulseSnapshot(statuses: [:], events: [])
    @State private var entitlementState: LocalEntitlementState = .fallback
    @StateObject private var keepAwakeService: KeepAwakeService
    @StateObject private var presentationModeService: PresentationModeService
    @StateObject private var handMirrorService = HandMirrorService()
    @StateObject private var displayControlService = DisplayControlService()
    @StateObject private var sceneNetworkStatusService = SceneNetworkStatusService()
    @StateObject private var colorPickerService = ColorPickerService()
    @StateObject private var calendarService = CalendarService()
    @StateObject private var networkMonitorService = NetworkMonitorService()
    @StateObject private var appAudioService = AppAudioService()
    @StateObject private var fnKeyService = FnKeyService()
    @StateObject private var totpService = TOTPService()
    @StateObject private var pomodoroService = PomodoroService()
    @StateObject private var subtitleService = SubtitleService()
    @StateObject private var textExpansionService = TextExpansionService()
    @StateObject private var hostsService = HostsService()
    @StateObject private var browserRouterService = BrowserRouterService()
    @StateObject private var envService = EnvService()
    @StateObject private var diskUsageService = DiskUsageService()
    @StateObject private var proxyService = ProxyService()
    @StateObject private var rssService = RSSService()
    @StateObject private var quickSwitchService = QuickSwitchService()
    @StateObject private var chapterService = ChapterService()
    @StateObject private var appCleanerService = AppCleanerService()
    @StateObject private var aspectGuideService = AspectGuideService()
    @StateObject private var dragShelfService = DragShelfService()
    @StateObject private var batteryHealthService = BatteryHealthService()
    @StateObject private var watermarkService = WatermarkService()
    @StateObject private var obsService = OBSService()
    @StateObject private var teleprompterService = TeleprompterService()
    @StateObject private var webWallpaperService = WebWallpaperService()
    @StateObject private var keyboardDisplayService = KeyboardDisplayService()
    @StateObject private var scrollSmoothingService = ScrollSmoothingService()
    @StateObject private var gifProcessingService = GIFProcessingService()
    @StateObject private var altTabService = AltTabService()
    @StateObject private var colorSamplerService = ColorSamplerService()
    @StateObject private var recordingIndicatorService = RecordingIndicatorService()
    @StateObject private var screenRecordingService = ScreenRecordingService()
    @StateObject private var soundFeedbackService = SoundFeedbackService()
    @StateObject private var keyboardSoundService = KeyboardSoundService()
    @StateObject private var audioMeterService = AudioMeterService()
    @StateObject private var audioRecordingService = AudioRecordingService()
    @StateObject private var lanTransferService = LANTransferService()
    @StateObject private var translationPopupService = TranslationPopupService()
    @StateObject private var bluetoothBatteryService = BluetoothBatteryService()
    @StateObject private var noiseGateService = NoiseGateService()
    @StateObject private var packetMonitorService = PacketMonitorService()
    @StateObject private var nowPlayingService = NowPlayingService()
    @StateObject private var liveCaptionService = LiveCaptionService()
    @StateObject private var pluginsService = PluginsService()
    @StateObject private var notchService = NotchService()
    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var recordingEditorService = RecordingEditorService()
    @StateObject private var scriptingService = ScriptingService()
    @State private var isShowingHandMirror = false
    @State private var isShowingSceneEditor = false
    @State private var isShowingSceneDiagnostics = false
    /// Process-global so the one-time startup runs once per launch even if SwiftUI
    /// recreates the menu bar content view (it would reset a plain @State flag).
    private static var didStartModules = false
    @State private var revealedOnDemandSceneModules = Set<SceneModuleID>()
    @State private var revealedOnDemandSceneID: UUID?
    private let screenshotFeatureSettingsStore = ScreenshotFeatureSettingsStore()
    private let translationConfigurationStore = ScreenshotTranslationConfigurationStore()
    private let screenshotLibraryStore = ScreenshotLibraryStore()
    private let fallbackClipboardHistoryStore = ClipboardHistoryStore()
    private let screenshotDragOutputStore = ScreenshotDragOutputStore()
    private let scrollingCaptureService = ScreenshotScrollingCaptureService()
    private let gifRecorder = ScreenshotGIFRecorder()
    private let gifOutputStore = ScreenshotGIFOutputStore()
    private let hotkeyService: GlobalHotkeyService
    private let workspaceStore = WorkspaceStore()
    private let workspaceService = WorkspaceWindowService()
    private let tokenBarLedger = TokenBarLedger()
    private let localAILoadRefreshService = LocalAILoadRefreshService()
    private let entitlementService: EntitlementService
    private let featureStateStore: FeatureStateStoring
    private var sceneCoordinator: SceneCoordinator? {
        paletteState?.sceneCoordinator
    }
    private var audioHubService: AudioHubService? {
        paletteState?.audioHubService
    }
    private var bluetoothQuickActionsService: BluetoothQuickActionsService? {
        paletteState?.bluetoothQuickActionsService
    }
    private var flowInboxStore: FlowInboxStore {
        paletteState?.flowInboxStore ?? FlowInboxStore()
    }
    private var scratchpadStore: ScratchpadStore {
        paletteState?.sharedScratchpadStore ?? ScratchpadStore()
    }
    private var clipboardHistoryStore: ClipboardHistoryStoring {
        paletteState?.clipboardHistoryStore ?? fallbackClipboardHistoryStore
    }
    private let scratchpadSummarizer = DisabledScratchpadSummarizer()
    let windowManager: WindowManaging
    let windowPermissionChecker: WindowManagementPermissionChecking
    var paletteState: CommandPaletteState?
    /// Where this view is hosted right now (menu bar popover vs. main window).
    /// The same view instance migrates between the two, so layout must react.
    @ObservedObject var shellMode: ShellModeModel
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var selectedShellTool: PrimaryPanelSection = .screenshot
    @State private var selectedShellTab: ShellToolTab = .overview
    @State private var shellTab: ShellTab = .general
    @State private var pluginsSelection: PluginsTab.Selection = .dashboard
    @State private var shellPage: ShellPage = .dashboard
    @StateObject private var menuWidgetStore = WidgetStore()
    @StateObject private var menuBluetoothBattery = BluetoothBatteryService()
    @State private var shellReturnPage: ShellPage = .dashboard
    @State private var shellLibraryQuery: String = ""
    @State private var dashboardTools: [String] = ShellToolPrefs.loadDashboard()
    @State private var favoriteShellTools: Set<String> = ShellToolPrefs.loadFavorites()
    @State private var popoverHiddenTools: Set<String> = ShellToolPrefs.loadHiddenInPopover()
    private let privacyPulseService: PrivacyPulseService
    private let privacyAccessLogger: PrivacyPulseAccessLogging

    init(
        windowManager: WindowManaging = AccessibilityWindowManager(),
        windowPermissionChecker: WindowManagementPermissionChecking = AccessibilityPermissionChecker(),
        entitlementService: EntitlementService = EntitlementService(provider: EntitlementProviderFactory.make()),
        featureStateStore: FeatureStateStoring = FeatureStateStore(),
        paletteState: CommandPaletteState? = nil,
        privacyPulseService: PrivacyPulseService = PrivacyPulseService(
            statusProvider: PrivacyPulseSystemStatusProvider(),
            eventStore: PrivacyPulseAccessLogger()
        ),
        privacyAccessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger(),
        shellMode: ShellModeModel = ShellModeModel()
    ) {
        let keepAwakeService = KeepAwakeService()
        _keepAwakeService = StateObject(wrappedValue: keepAwakeService)
        _presentationModeService = StateObject(wrappedValue: PresentationModeService(keepAwakeService: keepAwakeService))
        self.windowManager = windowManager
        self.windowPermissionChecker = windowPermissionChecker
        self.entitlementService = entitlementService
        self.featureStateStore = featureStateStore
        self.paletteState = paletteState
        self.privacyPulseService = privacyPulseService
        self.privacyAccessLogger = privacyAccessLogger
        self.hotkeyService = GlobalHotkeyService(accessLogger: privacyAccessLogger)
        self.shellMode = shellMode
    }

    var body: some View {
        ZStack {
            if shellMode.isMainWindow {
                mainShellView
            } else {
                menuPanelView
            }

            if let capturedScreenshot {
                ScreenshotEditorView(
                    screenshot: capturedScreenshot,
                    capabilities: screenshotFeatureSettings.editorCapabilities,
                    onCopy: copyScreenshot,
                    onSave: saveScreenshot,
                    onPin: pinScreenshot,
                    recognizedText: recognizedScreenshotText,
                    isRecognizingText: isRecognizingScreenshotText,
                    translatedText: translatedScreenshotText,
                    isTranslatingText: isTranslatingScreenshotText,
                    onRecognizeText: recognizeScreenshotText,
                    onCopyRecognizedText: copyRecognizedText,
                    onTranslateRecognizedText: translateRecognizedScreenshotText,
                    onCopyTranslatedText: copyTranslatedText,
                    onClose: closeScreenshotEditor
                )
            }
        }
        .sheet(isPresented: $isShowingHandMirror) {
            CameraPreviewPanel(
                permissionState: handMirrorService.permissionState,
                onRequestAccess: openHandMirror
            )
            .padding()
        }
        .sheet(isPresented: $isShowingSceneEditor) {
            if let sceneCoordinator {
                SceneEditorView(coordinator: sceneCoordinator)
            }
        }
        .sheet(isPresented: $isShowingSceneDiagnostics) {
            if let sceneCoordinator {
                SceneDiagnosticsView(coordinator: sceneCoordinator)
            }
        }
        .onAppear(perform: startModules)
        // Intentionally no `.onDisappear(stopModules)`: this is a menu bar agent,
        // so monitoring, the global hotkey, and the Scene System must keep running
        // while the popover is closed. They're torn down on app termination.
        .onReceive(NotificationCenter.default.publisher(for: .tokenBarSummaryDidChange)) { notification in
            if let summary = notification.object as? TokenBarSummary {
                tokenBarSummary = summary
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .atlasEntitlementDidChange)) { _ in
            refreshEntitlement()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tokenBarCommandStatusDidChange)) { notification in
            if let status = notification.object as? TokenBarCommandStatus {
                showStatus(status.message, kind: status.kind == .success ? .success : .error)
            }
        }
    }

    /// The designed Shell (`Atlas Shell.dc.html`) as the menu bar home, backed by
    /// real monitoring/feature/scene data and wired to real actions.
    @State private var visitedShellTabs: Set<ShellTab> = [.general]

    @ViewBuilder
    private func shellTabBody(_ tab: ShellTab) -> some View {
        switch tab {
        case .general:
            if let paletteState {
                GeneralSettingsTab(
                    shellThemeRaw: $shellThemeRaw,
                    paletteState: paletteState,
                    onOpenCommands: {
                        shellTab = .plugins
                        pluginsSelection = .commands
                    }
                )
            } else {
                Text("初始化中…").foregroundColor(.secondary)
            }
        case .plugins:
            pluginsTabView
        case .ai:
            AITabView()
        case .about:
            AboutTabView()
        }
    }

    // MARK: - Plugins tab (sidebar layout)

    @ViewBuilder
    private var pluginsTabView: some View {
        if let paletteState {
            PluginsTab(
                selection: $pluginsSelection,
                toolEntries: orderedPrimarySections().map { section in
                    PluginsTab.ToolEntry(
                        id: AnyHashable(section),
                        title: section.module.localizedTitle,
                        icon: ShellToolGroup.group(containing: section).icon
                    )
                },
                dashboardView: { AnyView(self.pluginsDashboard) },
                menuPanelConfigView: { AnyView(MenuPanelConfigView(store: self.menuWidgetStore)) },
                commandsView: {
                    AnyView(CommandsTableView(
                        aliases: paletteState.launcherAliases,
                        hotkeys: paletteState.launcherCommandHotkeys,
                        favorites: paletteState.launcherFavorites,
                        hotkeyConflicts: paletteState.commandHotkeyConflicts,
                        rootItems: { [weak controller = paletteState.controller] in
                            controller?.allRootItems() ?? []
                        }
                    ))
                },
                marketView: { AnyView(MarketView(service: self.pluginsService)) },
                toolView: { tag in AnyView(self.pluginsToolPage(tag)) }
            )
        } else {
            Text("初始化中…").foregroundColor(.secondary)
        }
    }

    private var pluginsDashboard: some View {
        Group {
            switch shellPage {
            case .dashboard:
                shellDashboard
            case .library:
                shellLibrary
            case .tool:
                shellToolPage
            }
        }
    }

    @ViewBuilder
    private func pluginsToolPage(_ tag: AnyHashable) -> some View {
        if let section = tag.base as? PrimaryPanelSection {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PermissionStatusSection(permissions: Self.permissions(for: section))
                    primaryPanelSection(section)
                        .glassCard(padding: 12)
                }
                .padding(14)
                .frame(maxWidth: 720, alignment: .leading)
            }
        } else {
            EmptyView()
        }
    }

    private static func permissions(for section: PrimaryPanelSection) -> [ToolPermission] {
        switch section {
        case .windowManager, .altTab:
            return [.accessibility]
        case .screenshot, .recordingIndicator, .recordingEditor:
            return [.screenRecording]
        case .liveCaption, .subtitles:
            return [.screenRecording]
        default:
            return []
        }
    }

    // MARK: - MacTools-style menu bar panel

    private var menuPanelView: some View {
        ZStack {
            shellThemeBackground
            MenuPanelView(
                widgetStore: menuWidgetStore,
                widgetContent: { kind in AnyView(self.menuWidget(for: kind)) },
                statusBanner: showCaptureStatus
                    ? AnyView(CaptureStatusBanner(message: captureStatus, kind: captureStatusKind))
                    : nil,
                onOpenMainWindow: { AtlasServices.shared.openMainWindow?() },
                onQuit: { NSApp.terminate(nil) }
            )
        }
        .environment(\.shellThemeKind, shellTheme)
        .environment(\.colorScheme, shellThemeColorScheme)
        .onAppear { shellTheme.applyGlobalAppearance() }
        .onChange(of: shellThemeRaw) { _ in shellTheme.applyGlobalAppearance() }
    }

        @ViewBuilder
    private func menuWidget(for kind: WidgetKind) -> some View {
        switch kind {
        case .gauges:
            GaugeQuadWidget(
                cpuPercent: snapshot.map { Double($0.cpuUsage) },
                memUsedBytes: snapshot.map { Double($0.memUsedBytes) },
                memTotalBytes: snapshot.map { Double($0.memTotalBytes) },
                diskUsedBytes: menuRootDisk.map { Double($0.usedBytes) },
                diskTotalBytes: menuRootDisk.map { Double($0.totalBytes) },
                batteryPercent: (snapshot?.battery).map { Double($0.chargePercent) },
                batteryCharging: snapshot?.battery?.isCharging ?? false,
                onEnableMonitoring: { self.enabledFeatures["monitoring"] = true
                    self.handleFeatureChange("monitoring", enabled: true) }
            )
        case .network:
            NetworkWidget(
                downloadBps: snapshot?.netDownloadBps,
                uploadBps: snapshot?.netUploadBps
            )
        case .processTop:
            ProcessTopWidget(rows: (snapshot?.topCpuProcesses ?? []).prefix(5).map { process in
                ProcessTopWidget.Row(
                    id: "\(process.pid)",
                    name: process.name,
                    cpuText: "\(Int(process.cpuUsage.rounded()))%",
                    memText: String(format: "%.0fM", Double(process.memBytes) / 1_048_576)
                )
            })
        case .calendar:
            CalendarWidget()
        case .deviceBattery:
            DeviceBatteryWidget(
                devices: menuBluetoothBattery.devices.map { device in
                    DeviceBatteryWidget.Device(
                        id: device.name,
                        name: device.name,
                        icon: "headphones",
                        percent: device.percent
                    )
                }
            )
            .onAppear { menuBluetoothBattery.refresh() }
        }
    }

    private var menuRootDisk: MonitoringDiskSnapshot? {
        let disks = snapshot?.disks ?? []
        return disks.first { $0.mountPoint == "/" } ?? disks.first
    }

    private static func openPreferencesWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Main window shell (top category tabs + tool sidebar + detail)

    @AppStorage("atlas.shell.theme") private var shellThemeRaw = ShellThemeKind.plain.rawValue

    private var shellTheme: ShellThemeKind {
        ShellThemeKind(rawValue: shellThemeRaw) ?? .plain
    }

    private var shellThemeColorScheme: ColorScheme {
        shellTheme.spec.colorScheme ?? systemColorScheme
    }

    private var mainShellView: some View {
        ZStack {
            shellThemeBackground
            VStack(alignment: .leading, spacing: 8) {
                // Lives in the transparent titlebar zone, right-aligned with
                // the traffic lights.
                shellTitlebarAccessory
                    .frame(height: 44)
                    .padding(.top, 8)
                // 访问过的 tab 常驻视图树,切换只改透明度 —— 避免整棵重建卡顿。
                ZStack(alignment: .topLeading) {
                    ForEach(ShellTab.allCases) { tab in
                        if visitedShellTabs.contains(tab) {
                            shellTabBody(tab)
                                .opacity(shellTab == tab ? 1 : 0)
                                .allowsHitTesting(shellTab == tab)
                                .accessibilityHidden(shellTab != tab)
                        }
                    }
                }
                .onChange(of: shellTab) { tab in
                    visitedShellTabs.insert(tab)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .ignoresSafeArea(edges: .top)
        }
        .noDefaultFocus()
        .onAppear { shellTheme.applyGlobalAppearance() }
        .onChange(of: shellThemeRaw) { _ in shellTheme.applyGlobalAppearance() }
        .environment(\.shellThemeKind, shellTheme)
        // Stage-locked themes override the system appearance: 3D Elements is
        // always a dark stage, Biophilic always a sunlit light one.
        .environment(\.colorScheme, shellThemeColorScheme)
        .frame(minWidth: 960, minHeight: 620)
        .onChange(of: selectedShellTool) { newTool in
            if newTool.tabs.contains(selectedShellTab) == false {
                selectedShellTab = .overview
            }
        }
    }

    private func openShellTool(_ section: PrimaryPanelSection) {
        selectedShellTool = section
        selectedShellTab = .overview
        shellReturnPage = shellPage == .tool ? shellReturnPage : shellPage
        shellPage = .tool
    }

    private func shellBackButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    // MARK: Dashboard

    private var dashboardSections: [PrimaryPanelSection] {
        dashboardTools.compactMap { PrimaryPanelSection.section(forFeatureName: $0) }
    }

    private var shellDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("工具台")
                    .font(.title2.weight(.semibold))

                if showCaptureStatus {
                    CaptureStatusBanner(message: captureStatus, kind: captureStatusKind)
                        .glassCard(padding: 10)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(dashboardSections, id: \.self) { section in
                        dashboardCard(section)
                    }
                    dashboardAddCard
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dashboardCard(_ section: PrimaryPanelSection) -> some View {
        Button {
            openShellTool(section)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: ShellToolGroup.group(containing: section).icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(section.module.localizedTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Circle()
                        .fill(isFeatureEnabled(section.module) ? Color.green.opacity(0.9) : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }

                dashboardCardBody(section)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
        .glassCard(cornerRadius: 14, padding: 14)
        .contextMenu {
            Button("从工具台移除") {
                dashboardTools.removeAll { $0 == section.module.featureName }
                ShellToolPrefs.saveDashboard(dashboardTools)
            }
            Button("打开设置") {
                openShellTool(section)
                selectedShellTab = .settings
            }
        }
    }

    @ViewBuilder
    private func dashboardCardBody(_ section: PrimaryPanelSection) -> some View {
        if isFeatureEnabled(section.module) {
            switch section {
            case .screenshot:
                HStack(spacing: 6) {
                    dashboardQuickAction("全屏", action: captureDesktop)
                    dashboardQuickAction("区域", action: showSelectionWindow)
                    dashboardQuickAction("窗口", action: showWindowSelection)
                }
            case .monitoring:
                if let snapshot {
                    Text("CPU \(Int(snapshot.cpuUsage.rounded()))% · 内存 \(String(format: "%.1f", Double(snapshot.memUsedBytes) / 1_073_741_824)) GB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("采集中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .clipboard:
                Text("\(clipboardHistoryItems.count) 条记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                Text("已启用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("未启用 · 点击进入开启")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dashboardQuickAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private var dashboardAddCard: some View {
        Button {
            shellPage = .library
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                Text("添加工具")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 78)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    // MARK: Library

    private var shellLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                shellBackButton("工具台") {
                    shellPage = .dashboard
                }
                Text("全部工具")
                    .font(.headline)
                Spacer()
                TextField("搜索工具…", text: $shellLibraryQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ShellToolGroup.allCases) { group in
                        let sections = librarySections(in: group)
                        if sections.isEmpty == false {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(group.title, systemImage: group.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(sections, id: \.self) { section in
                                    libraryRow(section)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func librarySections(in group: ShellToolGroup) -> [PrimaryPanelSection] {
        let query = shellLibraryQuery.trimmingCharacters(in: .whitespaces)
        guard query.isEmpty == false else { return group.sections }
        return group.sections.filter {
            $0.module.localizedTitle.localizedCaseInsensitiveContains(query)
                || $0.module.title.localizedCaseInsensitiveContains(query)
        }
    }

    private func libraryRow(_ section: PrimaryPanelSection) -> some View {
        let isAdded = dashboardTools.contains(section.module.featureName)
        return HStack(spacing: 10) {
            Circle()
                .fill(isFeatureEnabled(section.module) ? Color.green.opacity(0.9) : Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)
            Button {
                openShellTool(section)
            } label: {
                Text(section.module.localizedTitle)
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            if favoriteShellTools.contains(section.module.featureName) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
            Spacer()
            Button(isAdded ? "移除" : "添加") {
                if isAdded {
                    dashboardTools.removeAll { $0 == section.module.featureName }
                } else {
                    dashboardTools.append(section.module.featureName)
                }
                ShellToolPrefs.saveDashboard(dashboardTools)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassCard(cornerRadius: 10, padding: 2)
    }

    // MARK: Tool page

    private var shellToolPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                shellBackButton(shellReturnPage == .library ? "全部工具" : "工具台") {
                    shellPage = shellReturnPage
                }
                shellToolTabBar
            }
            shellDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var shellTitlebarAccessory: some View {
        HStack(spacing: 12) {
            Spacer()

            ShellTabBar(selection: $shellTab)

            Spacer()

            // Hidden ⌘1-⌘5 tab switchers.
            ForEach(ShellTab.allCases) { tab in
                Button("") { shellTab = tab }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(tab.shortcutDigit)")),
                        modifiers: .command
                    )
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }

        }
        .padding(.trailing, 14)
    }

    private var shellThemeBackground: some View {
        shellTheme.spec.makeBackground()
    }

    /// Per-tool tabs, top-aligned with the sidebar columns.
    private var shellToolTabBar: some View {
        HStack(spacing: 6) {
            ForEach(selectedShellTool.tabs, id: \.self) { tab in
                ShellTabButton(
                    title: tab.title,
                    icon: tab.icon,
                    isSelected: selectedShellTab == tab
                ) {
                    selectedShellTab = tab
                }
            }

            Spacer()
        }
        .frame(height: 28)
    }

    private var shellDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                shellDetailHeader
                    .glassCard()

                if showCaptureStatus {
                    CaptureStatusBanner(message: captureStatus, kind: captureStatusKind)
                        .glassCard(padding: 10)
                }

                shellTabContent
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var shellTabContent: some View {
        switch selectedShellTab {
        case .overview:
            if isFeatureEnabled(selectedShellTool.module) {
                VStack(alignment: .leading, spacing: 12) {
                    primaryPanelSection(selectedShellTool)
                }
                .glassCard()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("此工具未启用")
                        .font(.headline)
                    Text(shellDisabledHint(for: selectedShellTool.module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .glassCard()
            }
        case .library:
            ScreenshotLibraryPanel(
                items: screenshotLibraryItems,
                onOpen: openLibraryItem,
                onDelete: deleteLibraryItem,
                pngURL: { screenshotLibraryStore.pngURL(for: $0) },
                onRunOCR: screenshotFeatureSettings.editorCapabilities.ocr ? runBackgroundOCR : nil,
                onRunTranslation: screenshotFeatureSettings.editorCapabilities.translation && isTranslationConfigured ? runBackgroundTranslation : nil,
                onUpdateTags: updateLibraryItemTags,
                onCopyText: { text in
                    copyTextToClipboard(text, detail: "Screenshot library copied recognized text to the pasteboard")
                    showStatus("Copied text")
                },
                query: $screenshotLibraryQuery
            )
            .glassCard()
        case .settings:
            shellToolSettings
                .glassCard()
        case .translation:
            TranslationSettingsPanel(
                draft: translationSettingsDraft,
                isConfigured: isTranslationConfigured,
                onSave: saveTranslationSettings,
                onClear: clearTranslationSettings
            )
            .id(translationSettingsPanelIdentity)
            .glassCard()
        }
    }

    private var shellDetailHeader: some View {
        HStack(spacing: 12) {
            Text(selectedShellTool.module.localizedTitle)
                .font(.title2.weight(.semibold))

            let availability = featureAvailability(selectedShellTool.module.featureName)
            if availability.isAvailable == false {
                Text(availability.displayLabel)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }

            Spacer()

            Toggle("启用", isOn: shellFeatureBinding(for: selectedShellTool.module))
                .toggleStyle(.switch)
                .disabled(featureAvailability(selectedShellTool.module.featureName).isAvailable == false)
        }
    }

    private var shellToolSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("通用")
                .font(.headline)

            Toggle("启用此工具", isOn: shellFeatureBinding(for: selectedShellTool.module))
                .toggleStyle(.switch)
                .disabled(featureAvailability(selectedShellTool.module.featureName).isAvailable == false)

            Toggle("收藏（工具列表显示星标）", isOn: shellFavoriteBinding(for: selectedShellTool.module))
                .toggleStyle(.switch)

            Toggle("在菜单栏面板中显示", isOn: shellPopoverVisibilityBinding(for: selectedShellTool.module))
                .toggleStyle(.switch)

            shellToolSettingsBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var shellToolSettingsBody: some View {
        switch selectedShellTool {
        case .screenshot:
            Divider()

            Text("截图设置")
                .font(.headline)

            ScreenshotFeatureSettingsPanel(
                settings: screenshotFeatureSettings,
                onSave: saveScreenshotFeatureSettings
            )
            .id(screenshotFeatureSettingsIdentity)
        case .translation:
            Divider()

            Text("翻译设置")
                .font(.headline)

            TranslationSettingsPanel(
                draft: translationSettingsDraft,
                isConfigured: isTranslationConfigured,
                onSave: saveTranslationSettings,
                onClear: clearTranslationSettings
            )
            .id(translationSettingsPanelIdentity)
        default:
            EmptyView()
        }
    }

    private func shellFeatureBinding(for module: AtlasModule) -> Binding<Bool> {
        Binding(
            get: { enabledFeatures[module.featureName, default: false] },
            set: { handleFeatureChange(module.featureName, enabled: $0) }
        )
    }

    private func shellFavoriteBinding(for module: AtlasModule) -> Binding<Bool> {
        Binding(
            get: { favoriteShellTools.contains(module.featureName) },
            set: { isOn in
                if isOn {
                    favoriteShellTools.insert(module.featureName)
                } else {
                    favoriteShellTools.remove(module.featureName)
                }
                ShellToolPrefs.saveFavorites(favoriteShellTools)
            }
        )
    }

    private func shellPopoverVisibilityBinding(for module: AtlasModule) -> Binding<Bool> {
        Binding(
            get: { popoverHiddenTools.contains(module.featureName) == false },
            set: { isVisible in
                if isVisible {
                    popoverHiddenTools.remove(module.featureName)
                } else {
                    popoverHiddenTools.insert(module.featureName)
                }
                ShellToolPrefs.saveHiddenInPopover(popoverHiddenTools)
            }
        )
    }

    private func shellDisabledHint(for module: AtlasModule) -> String {
        let availability = featureAvailability(module.featureName)
        guard availability.isAvailable else {
            return "当前版本不可用：\(availability.displayLabel)"
        }
        return "使用右上角开关启用「\(module.localizedTitle)」。"
    }

    private static let historyMaxCount = 60

    /// Connects the Pomodoro timer to the Scene System: starting a focus session
    /// activates the "Focus" scene (auto-DND), per the roadmap's cross-cutting
    /// Scene integration.
    private func wirePomodoroToSceneSystem() {
        let paletteStateRef = paletteState
        pomodoroService.onFocusStarted = {
            guard let coordinator = paletteStateRef?.sceneCoordinator else { return }
            guard let focus = coordinator.scenes.first(where: { $0.name == "Focus" }) else { return }
            coordinator.activateScene(id: focus.id, reason: "Pomodoro focus session started")
        }
    }

    /// Screen recording start/stop; keeps the Recording Indicator's screen
    /// flag in sync (its detector can't see our own capture).
    private func toggleScreenRecording() {
        screenRecordingService.onRecordingStateChanged = { [weak recordingIndicatorService] isRecording in
            recordingIndicatorService?.setScreenRecording(isRecording)
        }
        if screenRecordingService.isRecording {
            screenRecordingService.stop()
        } else {
            screenRecordingService.start()
        }
    }

    private func startModules() {
        // `onAppear` fires every time the menu bar panel opens. Only run this
        // once per launch so the global hotkey + monitoring stay alive while the
        // panel is closed, and the accessibility prompt isn't shown repeatedly.
        guard !Self.didStartModules else { return }
        Self.didStartModules = true

        refreshEntitlement()

        loadScreenshotFeatureSettings()
        loadTranslationSettings()
        loadScreenshotLibrary()
        cleanupScreenshotDragOutput()
        CloudUploadHistoryStore().prune(expiryDays: CloudUploadConfigurationStore().load().historyExpiryDays)
        startHotkeys()
        wirePomodoroToSceneSystem()

        do {
            entitlementState = entitlementService.currentState()
            try AtlasBridge.configureEntitlement(entitlementState.edition)
            let loadedFeatures = try AtlasBridge.listFeatures()
            let synchronizedFeatures = try FeatureStateSynchronizer.restore(
                features: loadedFeatures,
                storedStates: featureStateStore.loadFeatureStates(),
                isAvailable: { entitlementService.availability(for: $0).isAvailable },
                toggle: AtlasBridge.toggleFeature
            )
            features = entitlementService.applyAvailability(to: synchronizedFeatures)
            enabledFeatures = FeatureStateReducer.enabledMap(from: synchronizedFeatures)
            featureStateStore.saveFeatureStates(enabledFeatures)
            configureSceneRuntime()
            paletteState?.setWindowManagementEnabled(isFeatureEnabled(.windowManager))
            paletteState?.setAudioHubEnabled(isFeatureEnabled(.audioHub))
            paletteState?.setFlowInboxEnabled(isFeatureEnabled(.flowInbox))
            paletteState?.setSceneSystemEnabled(isFeatureEnabled(.sceneSystem))
            paletteState?.setScratchpadEnabled(isFeatureEnabled(.scratchpad))
            syncClipboardFeatureGate()
            loadClipboardHistory()
            if isFeatureEnabled(.sceneSystem) {
                sceneNetworkStatusService.start()
            } else {
                sceneNetworkStatusService.stop()
            }
            tokenBarSummary = isFeatureEnabled(.tokenbar) ? ((try? tokenBarLedger.summary()) ?? .empty) : .empty
            statusText = "Atlas 已就绪"
            if isFeatureEnabled(.monitoring) {
                startMonitoring()
            }
            if isFeatureEnabled(.aiLoadMonitor) {
                startLocalAILoadRefresh()
            }
            if isFeatureEnabled(.privacy) {
                refreshPrivacyPulse()
            }
        } catch {
            statusText = "Atlas 功能加载失败"
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
        }
    }

    private func refreshEntitlement() {
        Task { @MainActor in
            await entitlementService.refresh()
            entitlementState = entitlementService.currentState()
            try? AtlasBridge.configureEntitlement(entitlementState.edition)
            features = entitlementService.applyAvailability(to: features)
        }
    }

    private var screenshotFeatureSettingsIdentity: String {
        ScreenshotSubfeature.allCases
            .map { screenshotFeatureSettings.isEnabled($0) ? "1" : "0" }
            .joined(separator: "")
    }

    private var translationSettingsPanelIdentity: String {
        [
            translationSettingsDraft.endpoint,
            translationSettingsDraft.apiKey,
            translationSettingsDraft.model,
            translationSettingsDraft.targetLanguage,
        ].joined(separator: "\u{1F}")
    }

    private func loadScreenshotFeatureSettings() {
        screenshotFeatureSettings = screenshotFeatureSettingsStore.load()
    }

    private func saveScreenshotFeatureSettings(_ settings: ScreenshotFeatureSettings) {
        screenshotFeatureSettingsStore.save(settings)
        loadScreenshotFeatureSettings()
        showStatus("Screenshot feature settings saved")
    }

    private func loadTranslationSettings() {
        translationSettingsDraft = translationConfigurationStore.settingsDraft()
        isTranslationConfigured = translationConfigurationStore.httpConfig() != nil
    }

    private func saveTranslationSettings(_ draft: ScreenshotTranslationSettingsDraft) {
        translationConfigurationStore.save(draft)
        loadTranslationSettings()
        showStatus(isTranslationConfigured ? "Translation settings saved" : "Translation endpoint is invalid", kind: isTranslationConfigured ? .success : .error)
    }

    private func clearTranslationSettings() {
        translationConfigurationStore.clear()
        loadTranslationSettings()
        showStatus("Translation settings cleared")
    }

    private func startHotkeys() {
        hotkeyService.requestAccessibilityIfNeeded()
        hotkeyService.onAreaCapture = { [self] in showSelectionWindow() }
        hotkeyService.start()
        paletteState?.setActions(
            onCaptureDesktop: { self.captureDesktop() },
            onCaptureArea: { self.showSelectionWindow() },
            onCaptureWindow: { self.showWindowSelection() },
            isSystemUtilitiesEnabled: { isFeatureEnabled(.systemUtilities) },
            onToggleKeepAwake: toggleKeepAwake,
            onTogglePresentationMode: togglePresentationMode,
            onOpenHandMirror: openHandMirror,
            onRefreshDisplays: refreshDisplays
        )

        if let controller = paletteState?.controller {
            controller.screenshotLibraryViewBuilder = {
                AnyView(
                    CommandPaletteScreenshotLibraryView(
                        store: self.screenshotLibraryStore,
                        onOpen: { item in
                            self.openLibraryItem(item)
                            controller.hide()
                        },
                        onDelete: { self.deleteLibraryItem($0) },
                        onRunOCR: self.screenshotFeatureSettings.editorCapabilities.ocr ? { self.runBackgroundOCR() } : nil,
                        onRunTranslation: self.screenshotFeatureSettings.editorCapabilities.translation && self.isTranslationConfigured ? { self.runBackgroundTranslation() } : nil,
                        onUpdateTags: { self.updateLibraryItemTags($0, tags: $1) },
                        onCopyText: { text in
                            self.copyTextToClipboard(text, detail: "Command palette screenshot library copied text to the pasteboard")
                            self.showStatus("Copied text")
                        }
                    )
                )
            }

            controller.portLookupViewBuilder = {
                AnyView(
                    MonitoringPortsPanel()
                )
            }

            controller.windowPickerViewBuilder = {
                let windows = (try? AtlasBridge.listCapturableWindows()) ?? []
                return AnyView(
                    WindowSelectionView(
                        windows: windows,
                        onCancel: {
                            controller.hide()
                        },
                        onSelect: { window in
                            self.captureWindow(window)
                            controller.hide()
                        }
                    )
                )
            }

            controller.workspaceViewBuilder = {
                AnyView(
                    WorkspacePanel(
                        model: workspacePanelModel()
                    )
                )
            }

            controller.tokenBarViewBuilder = {
                AnyView(TokenBarPanel(summary: tokenBarSummary))
            }

            controller.audioHubViewBuilder = {
                guard let audioHubService = self.audioHubService,
                      let bluetoothQuickActionsService = self.bluetoothQuickActionsService else {
                    return AnyView(Text("Audio Hub").padding())
                }
                return AnyView(
                    AudioHubPanel(
                        service: audioHubService,
                        bluetoothService: bluetoothQuickActionsService,
                        onManualAudioOverride: {
                            self.sceneCoordinator?.noteManualActionOverride("apply-audio-preset")
                        }
                    )
                    .padding()
                )
            }

            controller.flowInboxViewBuilder = {
                AnyView(
                    FlowInboxPanel(
                        store: self.flowInboxStore,
                        clipboardStore: self.clipboardHistoryStore,
                        screenshotStore: self.screenshotLibraryStore,
                        scratchpadStore: self.scratchpadStore,
                        behaviorRules: self.sceneCoordinator?.resolvedScene?.behaviorRules ?? .default,
                        skillStore: SkillStore(),
                        makeSkillRunner: SkillRuntimeFactory.makeDefaultRunner,
                        onOpenCommandPalette: { item in
                            self.showStatus("Opening commands for \(item.title)")
                            controller.hide()
                            DispatchQueue.main.async {
                                controller.show()
                            }
                        },
                        onShowStatus: { message in self.showStatus(message) }
                    )
                    .padding()
                )
            }

            controller.textToolboxViewBuilder = {
                AnyView(TextToolboxView())
            }

            controller.sceneEditorViewBuilder = {
                guard let sceneCoordinator = self.sceneCoordinator else {
                    return AnyView(Text("Scene Editor").padding())
                }
                return AnyView(SceneEditorView(coordinator: sceneCoordinator))
            }

            controller.sceneDiagnosticsViewBuilder = {
                guard let sceneCoordinator = self.sceneCoordinator else {
                    return AnyView(Text("Scene Diagnostics").padding())
                }
                return AnyView(SceneDiagnosticsView(coordinator: sceneCoordinator))
            }

            controller.scratchpadViewBuilder = { noteID in
                AnyView(
                    ScratchpadPanel(
                        store: self.scratchpadStore,
                        summarizer: self.scratchpadSummarizer,
                        initialSelectedNoteID: noteID
                    )
                )
            }
        }

        paletteState?.setWorkspaceActions(
            onSaveCurrent: saveCurrentWorkspaceFromPalette,
            onRestore: restoreWorkspaceFromPalette
        )
    }

    private func stopModules() {
        hotkeyService.stop()
        sceneCoordinator?.stop()
        sceneNetworkStatusService.stop()
        localAILoadRefreshService.stop()
        do {
            try AtlasBridge.stopMonitoring()
        } catch {
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
        }
    }

    private func handleFeatureChange(_ feature: String, enabled: Bool) {
        guard featureAvailability(feature).isAvailable else {
            enabledFeatures[feature] = false
            showStatus("\(featureTitle(feature)) is unavailable: \(featureAvailability(feature).displayLabel)", kind: .error)
            return
        }

        do {
            let changed = try AtlasBridge.toggleFeature(name: feature, enabled: enabled)
            guard changed else {
                enabledFeatures[feature] = FeatureStateReducer.rolledBackValue(forRequestedEnabled: enabled)
                showStatus("Unknown feature: \(feature)", kind: .error, autoHide: false)
                return
            }

            enabledFeatures[feature] = enabled
            featureStateStore.saveFeatureStates(enabledFeatures)
            refreshFeature(feature, enabled: enabled)
        } catch {
            enabledFeatures[feature] = FeatureStateReducer.rolledBackValue(forRequestedEnabled: enabled)
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
        }
    }

    private func refreshFeature(_ feature: String, enabled: Bool) {
        features = entitlementService.applyAvailability(
            to: FeatureStateReducer.refreshedFeatures(features, featureName: feature, enabled: enabled)
        )
        let affectsSceneRuntime = [
            AtlasModule.audioHub.featureName,
            AtlasModule.automation.featureName,
            AtlasModule.scratchpad.featureName,
            AtlasModule.skills.featureName,
            AtlasModule.systemUtilities.featureName,
        ].contains(feature)
        defer {
            if affectsSceneRuntime {
                configureSceneRuntime()
            }
        }

        if feature == AtlasModule.windowManager.featureName {
            paletteState?.setWindowManagementEnabled(enabled)
            return
        }

        if feature == AtlasModule.audioHub.featureName {
            paletteState?.setAudioHubEnabled(enabled)
            return
        }

        if feature == AtlasModule.flowInbox.featureName {
            paletteState?.setFlowInboxEnabled(enabled)
            return
        }

        if feature == AtlasModule.sceneSystem.featureName {
            configureSceneRuntime()
            paletteState?.setSceneSystemEnabled(enabled)
            if enabled {
                sceneNetworkStatusService.start()
            } else {
                sceneNetworkStatusService.stop()
            }
            return
        }

        if feature == AtlasModule.tokenbar.featureName {
            tokenBarSummary = enabled ? ((try? tokenBarLedger.summary()) ?? .empty) : .empty
            return
        }

        if feature == AtlasModule.scratchpad.featureName {
            paletteState?.setScratchpadEnabled(enabled)
            return
        }

        if feature == AtlasModule.clipboard.featureName {
            syncClipboardFeatureGate()
            loadClipboardHistory()
            refreshPrivacyPulseIfVisible()
            return
        }

        if feature == AtlasModule.privacy.featureName {
            if enabled {
                refreshPrivacyPulse()
            } else {
                privacyPulseSnapshot = PrivacyPulseSnapshot(statuses: [:], events: [])
            }
            return
        }

        if feature == AtlasModule.aiLoadMonitor.featureName {
            if enabled {
                startLocalAILoadRefresh()
            } else {
                localAILoadRefreshService.stop()
                localAILoadSnapshot = .empty
            }
            return
        }

        if feature == AtlasModule.networkMonitor.featureName {
            if enabled { networkMonitorService.startAutoRefresh() } else { networkMonitorService.stopAutoRefresh() }
            return
        }

        if feature == AtlasModule.appAudio.featureName {
            if enabled { appAudioService.refresh() }
            return
        }

        if feature == AtlasModule.fnKey.featureName {
            if enabled { fnKeyService.refresh() }
            return
        }

        if feature == AtlasModule.totp.featureName {
            if enabled { totpService.reload() }
            return
        }

        if feature == AtlasModule.pomodoro.featureName {
            if !enabled { pomodoroService.reset() }
            return
        }

        if feature == AtlasModule.textExpansion.featureName {
            if !enabled { textExpansionService.stopMonitoring() }
            return
        }

        if feature == AtlasModule.hosts.featureName {
            if enabled { hostsService.reload() }
            return
        }

        if feature == AtlasModule.calendar.featureName {
            if enabled { calendarService.requestAccessIfNeeded() }
            return
        }

        guard feature == AtlasModule.monitoring.featureName else { return }

        if enabled {
            startMonitoring()
            return
        }

        do {
            try AtlasBridge.stopMonitoring()
            snapshot = nil
        } catch {
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
        }
    }

    private func handleWindowGridResult(_ result: WindowGridSelectionResult) {
        switch result {
        case .performed:
            showStatus("Moved frontmost window")
        case .failed:
            showStatus("No active window to move", kind: .error)
        case .featureDisabled:
            showStatus("Window Manager is disabled", kind: .error)
        case .permissionRequired:
            showStatus("Accessibility permission is required", kind: .error)
        }
    }

    private func workspacePanelModel() -> WorkspacePanelModel {
        WorkspacePanelModel(
            store: workspaceStore,
            service: workspaceService,
            permissionChecker: windowPermissionChecker,
            isFeatureEnabled: { isFeatureEnabled(.windowManager) }
        )
    }

    private func saveCurrentWorkspaceFromPalette() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let name = "Workspace \(formatter.string(from: Date()))"
        let model = workspacePanelModel()

        do {
            try model.saveCurrentLayout(named: name)
            showStatus(model.statusMessage, kind: workspaceStatusKind(for: model))
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func restoreWorkspaceFromPalette(_ workspace: Workspace) {
        let model = workspacePanelModel()

        do {
            try model.restore(workspace)
            showStatus(model.statusMessage, kind: workspaceStatusKind(for: model))
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func workspaceStatusKind(for model: WorkspacePanelModel) -> CaptureStatusKind {
        if !model.restoreIssues.isEmpty {
            return .error
        }

        switch model.statusMessage {
        case "Window Manager is disabled",
             "Accessibility permission is required",
             "Workspace name is required":
            return .error
        default:
            return .success
        }
    }

    private func toggleKeepAwake() {
        sceneCoordinator?.noteManualActionOverride("toggle-keep-awake")
        if keepAwakeService.status == .running {
            keepAwakeService.stop()
            showStatus("Keep awake stopped")
            return
        }

        do {
            try keepAwakeService.start()
            showStatus("Keep awake started")
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func togglePresentationMode() {
        sceneCoordinator?.noteManualActionOverride("toggle-presentation-mode")
        if presentationModeService.status == .running {
            presentationModeService.stop()
            showStatus("Presentation mode stopped")
            return
        }

        do {
            try presentationModeService.start()
            showStatus("Presentation mode started")
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func openHandMirror() {
        Task {
            if await handMirrorService.prepareForPreview() {
                isShowingHandMirror = true
            } else {
                showStatus("Camera permission is required", kind: .error)
            }
        }
    }

    private func refreshDisplays() {
        do {
            try displayControlService.refreshDisplays()
            showStatus("Display capabilities refreshed")
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func loadClipboardHistory() {
        clipboardHistoryItems = clipboardHistoryStore.items()
    }

    private func copyClipboardHistoryText(_ text: String) {
        copyTextToClipboard(text, detail: "Clipboard history copied text to the pasteboard")
        showStatus("Copied clipboard item")
    }

    private func deleteClipboardHistoryItem(_ id: UUID) {
        clipboardHistoryStore.delete(id: id)
        loadClipboardHistory()
        showStatus("Clipboard item deleted")
    }

    private func clearClipboardHistory() {
        clipboardHistoryStore.clear()
        loadClipboardHistory()
        showStatus("Clipboard history cleared")
    }

    private func syncClipboardFeatureGate() {
        paletteState?.setClipboardHistoryEnabled(isFeatureEnabled(.clipboard))
        paletteState?.setClipboardHistoryChangedHandler {
            self.loadClipboardHistory()
        }
    }

    private func configureSceneRuntime() {
        guard let sceneCoordinator else { return }
        let isSystemUtilitiesEnabled = isFeatureEnabled(.systemUtilities)
        let isAudioHubEnabled = isFeatureEnabled(.audioHub)
        let isScratchpadEnabled = isFeatureEnabled(.scratchpad)
        sceneCoordinator.configure(
            runtimeContext: SceneRuntimeContext(
                toggleKeepAwake: isSystemUtilitiesEnabled ? toggleKeepAwakeForScene : nil,
                togglePresentationMode: isSystemUtilitiesEnabled ? togglePresentationModeForScene : nil,
                openHandMirror: isSystemUtilitiesEnabled ? openHandMirrorForScene : nil,
                refreshDisplays: isSystemUtilitiesEnabled ? refreshDisplaysForScene : nil,
                applyAudioPreset: isAudioHubEnabled ? { title in
                    audioHubService?.applyPreset(named: title)
                } : nil,
                runAutomation: isFeatureEnabled(.automation) ? { command in
                    await SystemAutomationProcessRunner().run(command)
                } : nil,
                runSkillNamed: isFeatureEnabled(.skills) ? { title in
                    let store = SkillStore()
                    guard let skill = store.skills().first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) else {
                        return false
                    }
                    do {
                        _ = try await SkillRuntimeFactory.makeDefaultRunner().run(skill)
                        return true
                    } catch {
                        return false
                    }
                } : nil,
                saveTextToScratchpad: isScratchpadEnabled ? { title, body in
                    try? scratchpadStore.create(ScratchpadDraft(title: title, markdown: body)).id
                } : nil,
                deleteScratchpadNote: isScratchpadEnabled ? { noteID in
                    try? scratchpadStore.delete(id: noteID)
                } : nil,
                registerSceneHotkey: { keyCode, modifiers, handler in
                    hotkeyService.register(
                        keyCode: keyCode,
                        modifiers: NSEvent.ModifierFlags(rawValue: modifiers),
                        handler: handler
                    )
                },
                unregisterSceneHotkey: { keyCode, modifiers in
                    hotkeyService.unregister(
                        keyCode: keyCode,
                        modifiers: NSEvent.ModifierFlags(rawValue: modifiers)
                    )
                },
                currentAudioDeviceNames: isAudioHubEnabled ? {
                    audioHubService?.currentDeviceNames ?? []
                } : nil,
                currentBluetoothDeviceNames: isAudioHubEnabled ? {
                    bluetoothQuickActionsService?.connectedDeviceNames ?? []
                } : nil,
                currentNetworkTriggerTokens: {
                    sceneNetworkStatusService.triggerTokens
                },
                currentDisplayTriggerTokens: {
                    currentDisplayTriggerTokens()
                },
                currentPowerStateTriggerTokens: {
                    currentPowerStateTriggerTokens()
                },
                currentIdleSeconds: {
                    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
                },
                currentKeepAwakeActive: {
                    keepAwakeService.status == .running
                },
                currentPresentationModeActive: {
                    presentationModeService.status == .running
                },
                currentAudioRoute: isAudioHubEnabled ? {
                    SceneAudioRoute(
                        outputDeviceID: audioHubService?.defaultOutputDeviceID,
                        inputDeviceID: audioHubService?.defaultInputDeviceID
                    )
                } : nil,
                restoreAudioRoute: isAudioHubEnabled ? { route in
                    if let outputDeviceID = route.outputDeviceID {
                        audioHubService?.setDefaultOutputDevice(outputDeviceID)
                    }
                    if let inputDeviceID = route.inputDeviceID {
                        audioHubService?.setDefaultInputDevice(inputDeviceID)
                    }
                    audioHubService?.refresh()
                } : nil,
                availableAudioPresetTitles: isAudioHubEnabled ? {
                    audioHubService?.presets.map(\.title) ?? []
                } : nil,
                availableSkillTitles: {
                    SkillStore().skills().map(\.title)
                },
                currentCameraPermissionState: {
                    handMirrorService.permissionState
                },
                moduleSnapshots: {
                    sceneModuleSnapshots()
                }
            )
        )
    }

    private func sceneModules() -> [AnySceneControllableModule] {
        [
            AnySceneControllableModule(
                AudioHubSceneModule(
                    isEnabled: isFeatureEnabled(.audioHub),
                    service: audioHubService
                )
            ),
            AnySceneControllableModule(
                FlowInboxSceneModule(
                    isEnabled: isFeatureEnabled(.flowInbox)
                )
            ),
            AnySceneControllableModule(
                SystemUtilitiesSceneModule(
                    isEnabled: isFeatureEnabled(.systemUtilities),
                    keepAwakeStatus: keepAwakeService.status,
                    presentationStatus: presentationModeService.status
                )
            ),
            AnySceneControllableModule(
                ScratchpadSceneModule(
                    isEnabled: isFeatureEnabled(.scratchpad)
                )
            ),
        ]
    }

    private func sceneModuleSnapshots() -> [SceneModuleCapabilitySnapshot] {
        sceneModules()
            .filter(\.isSceneControllable)
            .map { $0.capabilitySnapshot() }
    }

    private func currentDisplayTriggerTokens() -> [String] {
        var tokens = NSScreen.screens.compactMap(\.localizedName)
        tokens.append(NSScreen.screens.count > 1 ? "multiple-displays" : "single-display")
        return Array(Set(tokens)).sorted()
    }

    private func currentPowerStateTriggerTokens() -> [String] {
        var tokens: [String] = []

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            tokens.append("low-power")
        }

        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            if tokens.isEmpty {
                tokens.append("ac")
            }
            return Array(Set(tokens)).sorted()
        }

        let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
        let powerSourceState = (description[kIOPSPowerSourceStateKey as String] as? String) ?? ""
        let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Double
        let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Double

        if isCharging {
            tokens.append("charging")
            tokens.append("ac")
        } else if powerSourceState == kIOPSBatteryPowerValue {
            tokens.append("battery")
        } else {
            tokens.append("ac")
        }

        if let currentCapacity, let maxCapacity, maxCapacity > 0, (currentCapacity / maxCapacity) <= 0.2 {
            tokens.append("low-battery")
        }

        return Array(Set(tokens)).sorted()
    }

    private func revealOnDemandSceneModule(_ moduleID: SceneModuleID) {
        revealedOnDemandSceneID = sceneCoordinator?.activeSceneID
        revealedOnDemandSceneModules.insert(moduleID)
    }

    private func startMonitoring() {
        do {
            try AtlasBridge.startMonitoring { snapshot in
                DispatchQueue.main.async {
                    self.snapshot = snapshot
                    let cpu = Double(snapshot.cpuUsage)
                    let memRatio = Double(snapshot.memUsedBytes) / Double(max(1, snapshot.memTotalBytes)) * 100
                    self.cpuHistory = Array((self.cpuHistory + [cpu]).suffix(Self.historyMaxCount))
                    self.memoryHistory = Array((self.memoryHistory + [memRatio]).suffix(Self.historyMaxCount))
                }
            }
        } catch {
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
        }
    }

    private func toggleKeepAwakeForScene() {
        if keepAwakeService.status == .running {
            keepAwakeService.stop()
            return
        }
        try? keepAwakeService.start()
    }

    private func togglePresentationModeForScene() {
        if presentationModeService.status == .running {
            presentationModeService.stop()
            return
        }
        try? presentationModeService.start()
    }

    private func openHandMirrorForScene() {
        Task {
            if await handMirrorService.prepareForPreview() {
                isShowingHandMirror = true
            }
        }
    }

    private func refreshDisplaysForScene() {
        _ = try? displayControlService.refreshDisplays()
    }

    private func startLocalAILoadRefresh() {
        localAILoadRefreshService.start { snapshot in
            DispatchQueue.main.async {
                localAILoadSnapshot = snapshot
            }
        }
    }

    private func isFeatureEnabled(_ module: AtlasModule) -> Bool {
        featureAvailability(module.featureName).isAvailable && enabledFeatures[module.featureName, default: false]
    }

    private func orderedPrimarySections() -> [PrimaryPanelSection] {
        orderedPrimarySectionsUnfiltered().filter {
            popoverHiddenTools.contains($0.module.featureName) == false
        }
    }

    private func orderedPrimarySectionsUnfiltered() -> [PrimaryPanelSection] {
        let baseOrder: [PrimaryPanelSection] = [
            .sceneCenter,
            .audioHub,
            .flowInbox,
            .screenshot,
            .monitoring,
            .clipboard,
            .privacy,
            .aiLoad,
            .scratchpad,
            .systemUtilities,
            .tokenBar,
            .windowManager,
            .colorPicker,
            .ddcControl,
            .calendar,
            .networkMonitor,
            .appAudio,
            .fnKey,
            .totp,
            .pomodoro,
            .subtitles,
            .textExpansion,
            .hosts,
            .browserRouter,
            .envManager,
            .diskUsage,
            .proxy,
            .rss,
            .quickSwitches,
            .chapterMarker,
            .appCleaner,
            .aspectGuide,
            .dragShelf,
            .batteryHealth,
            .watermark,
            .obsControl,
            .teleprompter,
            .webWallpaper,
            .keyboardDisplay,
            .scrollSmoothing,
            .gifProcessing,
            .altTab,
            .colorSampler,
            .recordingIndicator,
            .soundFeedback,
            .keyboardSounds,
            .audioMeter,
            .audioRecording,
            .lanTransfer,
            .translation,
            .bluetoothBattery,
            .noiseGate,
            .packetMonitor,
            .nowPlaying,
            .liveCaption,
            .plugins,
            .notch,
            .transcription,
            .recordingEditor,
            .scripting,
        ]

        guard isFeatureEnabled(.sceneSystem), let sceneCoordinator else {
            return baseOrder
        }

        let defaultIndex = Dictionary(uniqueKeysWithValues: baseOrder.enumerated().map { ($1, $0) })
        return baseOrder.sorted { lhs, rhs in
            let lhsPriority = scenePanelOrder(for: lhs, coordinator: sceneCoordinator) ?? (100 + (defaultIndex[lhs] ?? 0))
            let rhsPriority = scenePanelOrder(for: rhs, coordinator: sceneCoordinator) ?? (100 + (defaultIndex[rhs] ?? 0))
            if lhsPriority == rhsPriority {
                return (defaultIndex[lhs] ?? 0) < (defaultIndex[rhs] ?? 0)
            }
            return lhsPriority < rhsPriority
        }
    }

    private func scenePanelOrder(for section: PrimaryPanelSection, coordinator: SceneCoordinator) -> Int? {
        switch section {
        case .sceneCenter:
            return -1
        case .audioHub:
            return coordinator.override(for: .audioHub)?.panelOrder
        case .flowInbox:
            return coordinator.override(for: .flowInbox)?.panelOrder
        case .screenshot:
            return coordinator.override(for: .screenshot)?.panelOrder
        case .monitoring:
            return coordinator.override(for: .monitoring)?.panelOrder
        case .clipboard:
            return coordinator.override(for: .clipboard)?.panelOrder
        case .privacy:
            return coordinator.override(for: .privacy)?.panelOrder
        case .aiLoad:
            return coordinator.override(for: .aiLoadMonitor)?.panelOrder
        case .scratchpad:
            return coordinator.override(for: .scratchpad)?.panelOrder
        case .systemUtilities:
            return coordinator.override(for: .systemUtilities)?.panelOrder
        case .tokenBar:
            return coordinator.override(for: .tokenbar)?.panelOrder
        case .windowManager:
            return coordinator.override(for: .windowManager)?.panelOrder
        case .colorPicker, .ddcControl, .calendar, .networkMonitor, .appAudio, .fnKey, .totp, .pomodoro, .subtitles, .textExpansion, .hosts, .browserRouter, .envManager, .diskUsage, .proxy, .rss, .quickSwitches, .chapterMarker, .appCleaner, .aspectGuide, .dragShelf, .batteryHealth, .watermark, .obsControl, .teleprompter, .webWallpaper, .keyboardDisplay, .scrollSmoothing, .gifProcessing, .altTab, .colorSampler, .recordingIndicator, .soundFeedback, .keyboardSounds, .audioMeter, .audioRecording, .lanTransfer, .translation, .bluetoothBattery, .noiseGate, .packetMonitor, .nowPlaying, .liveCaption, .plugins, .notch, .transcription, .recordingEditor, .scripting:
            return nil
        }
    }

    private func isSceneModuleVisible(_ sceneModuleID: SceneModuleID) -> Bool {
        guard isFeatureEnabled(.sceneSystem), let sceneCoordinator else {
            return true
        }
        guard let override = sceneCoordinator.override(for: sceneModuleID) else {
            return true
        }
        guard override.visibility != .hidden, override.state != .disabled else {
            return false
        }
        if override.state == .onDemand {
            let isRevealedForActiveScene = revealedOnDemandSceneID == sceneCoordinator.activeSceneID
                && revealedOnDemandSceneModules.contains(sceneModuleID)
            return override.visibility == .promoted || isRevealedForActiveScene
        }
        return true
    }

    @ViewBuilder
    private func primaryPanelSection(_ section: PrimaryPanelSection) -> some View {
        switch section {
        case .sceneCenter:
            if isFeatureEnabled(.sceneSystem), let sceneCoordinator {
                SceneCenterPanel(
                    coordinator: sceneCoordinator,
                    onOpenEditor: { isShowingSceneEditor = true },
                    onOpenDiagnostics: { isShowingSceneDiagnostics = true },
                    onRevealModule: revealOnDemandSceneModule
                )

                Divider()
            }
        case .audioHub:
            if isFeatureEnabled(.audioHub),
               isSceneModuleVisible(.audioHub),
               let audioHubService,
               let bluetoothQuickActionsService {
                AudioHubPanel(
                    service: audioHubService,
                    bluetoothService: bluetoothQuickActionsService,
                    onManualAudioOverride: {
                        sceneCoordinator?.noteManualActionOverride("apply-audio-preset")
                    }
                )

                Divider()
            }
        case .flowInbox:
            if isFeatureEnabled(.flowInbox), isSceneModuleVisible(.flowInbox) {
                FlowInboxPanel(
                    store: flowInboxStore,
                    clipboardStore: clipboardHistoryStore,
                    screenshotStore: screenshotLibraryStore,
                    scratchpadStore: scratchpadStore,
                    behaviorRules: sceneCoordinator?.resolvedScene?.behaviorRules ?? .default,
                    skillStore: SkillStore(),
                    makeSkillRunner: SkillRuntimeFactory.makeDefaultRunner,
                    onOpenCommandPalette: { item in
                        showStatus("Opening commands for \(item.title)")
                        paletteState?.controller.show()
                    },
                    onShowStatus: { message in showStatus(message) }
                )

                Divider()
            }
        case .screenshot:
            if isFeatureEnabled(.screenshot), isSceneModuleVisible(.screenshot) {
                ScreenshotPanel(
                    capabilities: screenshotFeatureSettings.captureCapabilities,
                    onCaptureDesktop: captureDesktop,
                    onCaptureWindow: showWindowSelection,
                    onCaptureArea: showSelectionWindow,
                    onCaptureScrolling: startScrollingWindowCapture,
                    onRecordGIF: startGIFRegionSelection,
                    isScreenRecording: screenRecordingService.isRecording,
                    onToggleScreenRecording: toggleScreenRecording
                )

                if let recordingError = screenRecordingService.errorMessage {
                    Text(recordingError)
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if isRecordingGIF {
                    HStack {
                        Label("Recording GIF", systemImage: "record.circle")
                        Spacer()
                        Button("Stop") {
                            gifRecordingSession?.cancel()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let lastGIFOutput, !isRecordingGIF {
                    HStack {
                        Label(lastGIFOutput.filename, systemImage: "photo.stack")
                            .lineLimit(1)
                        Spacer()
                        Button("Copy GIF", action: copyLastGIFRecording)
                            .buttonStyle(.bordered)
                        Button("Save As", action: saveLastGIFRecording)
                            .buttonStyle(.borderedProminent)
                    }
                }

                Divider()
            }
        case .monitoring:
            if isFeatureEnabled(.monitoring), isSceneModuleVisible(.monitoring) {
                MonitoringPanel(
                    snapshot: snapshot,
                    cpuHistory: cpuHistory,
                    memoryHistory: memoryHistory
                )

                Divider()
            }
        case .clipboard:
            if isFeatureEnabled(.clipboard), isSceneModuleVisible(.clipboard) {
                ClipboardHistoryPanel(
                    items: clipboardHistoryItems,
                    onCopyText: copyClipboardHistoryText,
                    onDelete: deleteClipboardHistoryItem,
                    onClear: clearClipboardHistory,
                    query: $clipboardHistoryQuery
                )

                Divider()
            }
        case .privacy:
            if isFeatureEnabled(.privacy), isSceneModuleVisible(.privacy) {
                PrivacyPulsePanel(
                    snapshot: privacyPulseSnapshot,
                    onRefresh: refreshPrivacyPulse
                )

                Divider()
            }
        case .aiLoad:
            if isFeatureEnabled(.aiLoadMonitor), isSceneModuleVisible(.aiLoadMonitor) {
                LocalAILoadPanel(snapshot: localAILoadSnapshot)

                Divider()
            }
        case .scratchpad:
            if isFeatureEnabled(.scratchpad), isSceneModuleVisible(.scratchpad) {
                ScratchpadPanel(
                    store: scratchpadStore,
                    summarizer: scratchpadSummarizer
                )

                Divider()
            }
        case .systemUtilities:
            if isFeatureEnabled(.systemUtilities), isSceneModuleVisible(.systemUtilities) {
                SystemUtilitiesPanel(
                    model: SystemUtilitiesPanelModel(
                        state: SystemUtilitiesState(
                            keepAwake: keepAwakeService.status,
                            presentationMode: presentationModeService.status,
                            cameraPermission: handMirrorService.permissionState,
                            displays: displayControlService.displays
                        ),
                        onToggleKeepAwake: toggleKeepAwake,
                        onTogglePresentationMode: togglePresentationMode,
                        onOpenHandMirror: openHandMirror,
                        onRefreshDisplays: refreshDisplays
                    )
                )

                Divider()
            }
        case .tokenBar:
            if isFeatureEnabled(.tokenbar), isSceneModuleVisible(.tokenbar) {
                TokenBarPanel(summary: tokenBarSummary)

                Divider()
            }
        case .windowManager:
            if isFeatureEnabled(.windowManager), isSceneModuleVisible(.windowManager) {
                WindowGridPanel(
                    model: WindowGridPanelModel(
                        windowManager: windowManager,
                        permissionChecker: windowPermissionChecker,
                        isFeatureEnabled: { isFeatureEnabled(.windowManager) }
                    ),
                    onResult: handleWindowGridResult
                )

                Divider()

                WorkspacePanel(
                    model: workspacePanelModel()
                )

                Divider()
            }
        case .colorPicker:
            if isFeatureEnabled(.colorPicker) {
                ColorPickerPanel(service: colorPickerService)
                Divider()
            }
        case .ddcControl:
            if isFeatureEnabled(.ddcControl) {
                DDCPanel(service: displayControlService)
                Divider()
            }
        case .calendar:
            if isFeatureEnabled(.calendar) {
                CalendarPanel(service: calendarService)
                Divider()
            }
        case .networkMonitor:
            if isFeatureEnabled(.networkMonitor) {
                NetworkMonitorPanel(service: networkMonitorService)
                Divider()
            }
        case .appAudio:
            if isFeatureEnabled(.appAudio) {
                AppAudioPanel(service: appAudioService)
                Divider()
            }
        case .fnKey:
            if isFeatureEnabled(.fnKey) {
                FnKeyPanel(service: fnKeyService)
                Divider()
            }
        case .totp:
            if isFeatureEnabled(.totp) {
                TOTPPanel(service: totpService)
                Divider()
            }
        case .pomodoro:
            if isFeatureEnabled(.pomodoro) {
                PomodoroPanel(service: pomodoroService)
                Divider()
            }
        case .subtitles:
            if isFeatureEnabled(.subtitles) {
                SubtitlePanel(service: subtitleService)
                Divider()
            }
        case .textExpansion:
            if isFeatureEnabled(.textExpansion) {
                TextExpansionPanel(service: textExpansionService)
                Divider()
            }
        case .hosts:
            if isFeatureEnabled(.hosts) {
                HostsPanel(service: hostsService)
                Divider()
            }
        case .browserRouter:
            if isFeatureEnabled(.browserRouter) {
                BrowserRouterPanel(service: browserRouterService)
                Divider()
            }
        case .envManager:
            if isFeatureEnabled(.envManager) {
                EnvPanel(service: envService)
                Divider()
            }
        case .diskUsage:
            if isFeatureEnabled(.diskUsage) {
                DiskUsagePanel(service: diskUsageService)
                Divider()
            }
        case .proxy:
            if isFeatureEnabled(.proxy) {
                ProxyPanel(service: proxyService)
                Divider()
            }
        case .rss:
            if isFeatureEnabled(.rss) {
                RSSPanel(service: rssService)
                Divider()
            }
        case .quickSwitches:
            if isFeatureEnabled(.quickSwitches) {
                QuickSwitchPanel(service: quickSwitchService)
                Divider()
            }
        case .chapterMarker:
            if isFeatureEnabled(.chapterMarker) {
                ChapterPanel(service: chapterService)
                Divider()
            }
        case .appCleaner:
            if isFeatureEnabled(.appCleaner) {
                AppCleanerPanel(service: appCleanerService)
                Divider()
            }
        case .aspectGuide:
            if isFeatureEnabled(.aspectGuide) {
                AspectGuidePanel(service: aspectGuideService)
                Divider()
            }
        case .dragShelf:
            if isFeatureEnabled(.dragShelf) {
                DragShelfPanel(service: dragShelfService)
                Divider()
            }
        case .batteryHealth:
            if isFeatureEnabled(.batteryHealth) {
                BatteryHealthPanel(service: batteryHealthService)
                Divider()
            }
        case .watermark:
            if isFeatureEnabled(.watermark) {
                WatermarkPanel(service: watermarkService)
                Divider()
            }
        case .obsControl:
            if isFeatureEnabled(.obsControl) {
                OBSPanel(service: obsService)
                Divider()
            }
        case .teleprompter:
            if isFeatureEnabled(.teleprompter) {
                TeleprompterPanel(service: teleprompterService)
                Divider()
            }
        case .webWallpaper:
            if isFeatureEnabled(.webWallpaper) {
                WebWallpaperPanel(service: webWallpaperService)
                Divider()
            }
        case .keyboardDisplay:
            if isFeatureEnabled(.keyboardDisplay) {
                KeyboardDisplayPanel(service: keyboardDisplayService)
                Divider()
            }
        case .scrollSmoothing:
            if isFeatureEnabled(.scrollSmoothing) {
                ScrollSmoothingPanel(service: scrollSmoothingService)
                Divider()
            }
        case .gifProcessing:
            if isFeatureEnabled(.gifProcessing) {
                GIFProcessingPanel(service: gifProcessingService)
                Divider()
            }
        case .altTab:
            if isFeatureEnabled(.altTab) {
                AltTabPanel(service: altTabService)
                Divider()
            }
        case .colorSampler:
            if isFeatureEnabled(.colorSampler) {
                ColorSamplerPanel(service: colorSamplerService)
                Divider()
            }
        case .recordingIndicator:
            if isFeatureEnabled(.recordingIndicator) {
                RecordingIndicatorPanel(service: recordingIndicatorService)
                Divider()
            }
        case .soundFeedback:
            if isFeatureEnabled(.soundFeedback) {
                SoundFeedbackPanel(service: soundFeedbackService)
                Divider()
            }
        case .keyboardSounds:
            if isFeatureEnabled(.keyboardSounds) {
                KeyboardSoundPanel(service: keyboardSoundService)
                Divider()
            }
        case .audioMeter:
            if isFeatureEnabled(.audioMeter) {
                AudioMeterPanel(service: audioMeterService)
                Divider()
            }
        case .audioRecording:
            if isFeatureEnabled(.audioRecording) {
                AudioRecordingPanel(service: audioRecordingService)
                Divider()
            }
        case .lanTransfer:
            if isFeatureEnabled(.lanTransfer) {
                LANTransferPanel(service: lanTransferService)
                Divider()
            }
        case .translation:
            if isFeatureEnabled(.translation) {
                TranslationPopupPanel(service: translationPopupService)
                Divider()
            }
        case .bluetoothBattery:
            if isFeatureEnabled(.bluetoothBattery) {
                BluetoothBatteryPanel(service: bluetoothBatteryService)
                Divider()
            }
        case .noiseGate:
            if isFeatureEnabled(.noiseGate) {
                NoiseGatePanel(service: noiseGateService)
                Divider()
            }
        case .packetMonitor:
            if isFeatureEnabled(.packetMonitor) {
                PacketMonitorPanel(service: packetMonitorService)
                Divider()
            }
        case .nowPlaying:
            if isFeatureEnabled(.nowPlaying) {
                NowPlayingPanel(service: nowPlayingService)
                Divider()
            }
        case .liveCaption:
            if isFeatureEnabled(.liveCaption) {
                LiveCaptionPanel(service: liveCaptionService)
                Divider()
            }
        case .plugins:
            if isFeatureEnabled(.plugins) {
                PluginsPanel(service: pluginsService)
                Divider()
            }
        case .notch:
            if isFeatureEnabled(.notch) {
                NotchPanel(service: notchService)
                Divider()
            }
        case .transcription:
            if isFeatureEnabled(.transcription) {
                TranscriptionPanel(service: transcriptionService)
                Divider()
            }
        case .recordingEditor:
            if isFeatureEnabled(.recordingEditor) {
                RecordingEditorPanel(service: recordingEditorService)
                Divider()
            }
        case .scripting:
            if isFeatureEnabled(.scripting) {
                ScriptingPanel(service: scriptingService)
                Divider()
            }
        }
    }

    private func featureAvailability(_ featureName: String) -> FeatureAvailability {
        features.first { $0.name == featureName }?.availability ?? entitlementService.availability(for: featureName)
    }

    private func featureTitle(_ featureName: String) -> String {
        features.first { $0.name == featureName }?.title ?? AtlasFeature(name: featureName, isEnabled: false).title
    }

    private func showSelectionWindow() {
        guard screenshotFeatureSettings.captureCapabilities.area else {
            showStatus("Area capture is disabled", kind: .error)
            return
        }

        startRegionSelection(onSelect: captureSelection)
    }

    private func startRegionSelection(onSelect: @escaping (CGRect) -> Void) {
        let previewImageData = selectionPreviewImageData()
        ScreenshotSelectionWindow.show(previewImageData: previewImageData, onCapture: onSelect)
    }

    private func selectionPreviewImageData() -> Data? {
        guard let screen = NSScreen.main else {
            return try? AtlasBridge.captureFullScreen()
        }

        let region = ScreenCaptureCoordinateMapper.pixelRegion(
            fromSelectionRect: CGRect(origin: .zero, size: screen.frame.size),
            backingScaleFactor: screen.backingScaleFactor
        )

        return try? AtlasBridge.captureRegion(
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height
        )
    }

    private func showWindowSelection() {
        guard screenshotFeatureSettings.captureCapabilities.window else {
            showStatus("Window capture is disabled", kind: .error)
            return
        }

        do {
            let windows = try AtlasBridge.listCapturableWindows()
            guard !windows.isEmpty else {
                showStatus("No capturable windows found", kind: .error)
                return
            }

            WindowSelectionWindow.show(
                windows: windows,
                onCancel: {},
                onSelect: captureWindow
            )
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func captureWindow(_ window: CapturableWindow) {
        do {
            let data = try AtlasBridge.captureWindow(id: window.id)

            guard let bitmap = NSBitmapImageRep(data: data) else {
                showStatus("Captured window image could not be decoded", kind: .error)
                return
            }

            let rect = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            setCapturedScreenshot(CapturedScreenshot(pngData: data, rect: rect), source: "Window")
            showStatus("Captured \(window.title)")
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func startScrollingWindowCapture() {
        guard screenshotFeatureSettings.captureCapabilities.scrolling else {
            showStatus("Scrolling capture is disabled", kind: .error)
            return
        }

        do {
            let windows = try AtlasBridge.listCapturableWindows()
            guard !windows.isEmpty else {
                showStatus("No capturable windows found", kind: .error)
                return
            }

            WindowSelectionWindow.show(
                windows: windows,
                onCancel: {},
                onSelect: captureScrollingWindow
            )
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func captureScrollingWindow(_ window: CapturableWindow) {
        do {
            let result = try scrollingCaptureService.capture(
                request: ScrollingCaptureRequest(
                    window: window,
                    maxFrames: 20,
                    scrollDelta: -900,
                    overlapPixels: 80
                )
            )
            let rect = CGRect(
                x: 0,
                y: 0,
                width: result.libraryItem.pixelWidth,
                height: result.libraryItem.pixelHeight
            )
            setCapturedScreenshot(
                CapturedScreenshot(
                    id: result.libraryItem.id,
                    pngData: result.pngData,
                    rect: rect,
                    capturedAt: result.libraryItem.capturedAt
                ),
                source: result.libraryItem.source,
                libraryItemID: result.libraryItem.id
            )
            loadScreenshotLibrary()
            showStatus("Captured scrolling window")
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func captureSelection(_ rect: CGRect) {
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let region = ScreenCaptureCoordinateMapper.pixelRegion(
            fromSelectionRect: rect,
            backingScaleFactor: scale
        )

        do {
            let data = try AtlasBridge.captureRegion(
                x: region.x,
                y: region.y,
                width: region.width,
                height: region.height
            )

            guard let bitmap = NSBitmapImageRep(data: data) else {
                showStatus("Captured region image could not be decoded", kind: .error)
                return
            }

            let pixelRect = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            setCapturedScreenshot(CapturedScreenshot(pngData: data, rect: pixelRect), source: "Area")
            showStatus("Captured \(bitmap.pixelsWide)×\(bitmap.pixelsHigh) px")
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func startGIFRegionSelection() {
        guard screenshotFeatureSettings.captureCapabilities.gifRecording else {
            showStatus("GIF recording is disabled", kind: .error)
            return
        }

        startRegionSelection(onSelect: startGIFRecording)
    }

    private func startGIFRecording(in region: CGRect) {
        let session = ScreenshotGIFRecordingSession()
        gifRecordingSession = session
        isRecordingGIF = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try gifRecorder.record(
                    request: ScreenshotGIFRecordingRequest(
                        region: region,
                        frameDelay: 0.12,
                        maximumFrames: 600
                    ),
                    shouldStop: { session.isCancelled }
                )
                let output = try gifOutputStore.writeTemporaryGIF(result.gifData)

                DispatchQueue.main.async {
                    lastGIFOutput = output
                    isRecordingGIF = false
                    gifRecordingSession = nil
                    showStatus("Saved GIF recording")
                }
            } catch {
                DispatchQueue.main.async {
                    isRecordingGIF = false
                    gifRecordingSession = nil
                    showStatus(error.localizedDescription, kind: .error)
                }
            }
        }
    }

    private func copyLastGIFRecording() {
        guard let lastGIFOutput else {
            showStatus("No GIF recording to copy", kind: .error)
            return
        }

        ScreenshotGIFPasteboardWriter.copy(lastGIFOutput)
        showStatus("Copied GIF recording")
    }

    private func saveLastGIFRecording() {
        guard let lastGIFOutput else {
            showStatus("No GIF recording to save", kind: .error)
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = lastGIFOutput.filename
        panel.allowedContentTypes = [.gif]
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: lastGIFOutput.url, to: destination)
            showStatus("Saved GIF recording")
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func captureDesktop() {
        guard screenshotFeatureSettings.captureCapabilities.desktop else {
            showStatus("Desktop capture is disabled", kind: .error)
            return
        }

        let data: Data

        do {
            data = try AtlasBridge.captureFullScreen()
        } catch {
            showStatus(error.localizedDescription, kind: .error)
            return
        }

        guard let bitmap = NSBitmapImageRep(data: data) else {
            showStatus("Captured full-screen image could not be decoded", kind: .error)
            return
        }

        let rect = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        setCapturedScreenshot(CapturedScreenshot(pngData: data, rect: rect), source: "Desktop")
        showStatus("Captured full screen")
    }

    private func setCapturedScreenshot(
        _ screenshot: CapturedScreenshot,
        source: String,
        libraryItemID existingLibraryItemID: UUID? = nil
    ) {
        invalidateScreenshotTextTasks()
        clearScreenshotTextState()
        capturedScreenshot = nil
        let libraryItemID = existingLibraryItemID ?? recordScreenshotInLibrary(screenshot, source: source)
        activeLibraryItemID = libraryItemID
        showFloatingThumbnail(for: screenshot, libraryItemID: libraryItemID)
    }

    private func closeScreenshotEditor() {
        invalidateScreenshotTextTasks()
        capturedScreenshot = nil
        activeLibraryItemID = nil
        annotatedScreenshotData = nil
        clearScreenshotTextState()
    }

    private func loadScreenshotLibrary() {
        do {
            screenshotLibraryItems = try screenshotLibraryStore.loadItems()
        } catch {
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
        }
    }

    private func cleanupScreenshotDragOutput() {
        do {
            try screenshotDragOutputStore.cleanupFiles(
                olderThan: ScreenshotDragOutputStore.cleanupCutoff()
            )
        } catch {
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
        }
    }

    private func recordScreenshotInLibrary(_ screenshot: CapturedScreenshot, source: String) -> UUID? {
        do {
            let item = try screenshotLibraryStore.addScreenshot(
                pngData: screenshot.pngData,
                pixelWidth: Int(screenshot.rect.width),
                pixelHeight: Int(screenshot.rect.height),
                source: source,
                capturedAt: screenshot.capturedAt
            )
            activeLibraryItemID = item.id
            loadScreenshotLibrary()
            return item.id
        } catch {
            activeLibraryItemID = nil
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
            return nil
        }
    }

    private func showFloatingThumbnail(for screenshot: CapturedScreenshot, libraryItemID: UUID?) {
        FloatingScreenshotThumbnailWindow.show(
            screenshot: screenshot,
            onOpen: {
                openFloatingThumbnail(screenshot, libraryItemID: libraryItemID)
            },
            onCopy: copyScreenshotFromThumbnail,
            onSave: saveScreenshotFromThumbnail,
            onDismiss: dismissFloatingThumbnail,
            onDragItemProvider: {
                dragItemProvider(for: screenshot)
            }
        )
    }

    private func dragItemProvider(for screenshot: CapturedScreenshot) -> NSItemProvider {
        let dragData = annotatedScreenshotData ?? screenshot.pngData
        do {
            return try screenshotDragOutputStore.makeItemProvider(
                pngData: dragData,
                id: screenshot.id,
                date: screenshot.capturedAt
            )
        } catch {
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
            return NSItemProvider(item: dragData as NSData, typeIdentifier: UTType.png.identifier)
        }
    }

    private func openFloatingThumbnail(
        _ screenshot: CapturedScreenshot,
        libraryItemID: UUID?
    ) -> FloatingScreenshotThumbnailActionResult {
        invalidateScreenshotTextTasks()
        activeLibraryItemID = libraryItemID
        capturedScreenshot = screenshot
        clearScreenshotTextState()
        showStatus("Opened screenshot editor")
        return .openedEditor
    }

    private func updateActiveLibraryItem(
        recognizedText: String? = nil,
        translatedText: String? = nil
    ) {
        guard let activeLibraryItemID else { return }

        do {
            try screenshotLibraryStore.updateText(
                id: activeLibraryItemID,
                recognizedText: recognizedText,
                translatedText: translatedText
            )
            loadScreenshotLibrary()
        } catch {
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
        }
    }

    private func openLibraryItem(_ item: ScreenshotLibraryItem) {
        do {
            let data = try screenshotLibraryStore.pngData(for: item)
            let rect = CGRect(x: 0, y: 0, width: item.pixelWidth, height: item.pixelHeight)
            invalidateScreenshotTextTasks()
            FloatingScreenshotThumbnailWindow.dismiss()
            activeLibraryItemID = item.id
            capturedScreenshot = CapturedScreenshot(
                id: item.id,
                pngData: data,
                rect: rect,
                capturedAt: item.capturedAt
            )
            recognizedScreenshotText = item.recognizedText
            translatedScreenshotText = item.translatedText
            isRecognizingScreenshotText = false
            isTranslatingScreenshotText = false
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func updateLibraryItemTags(_ item: ScreenshotLibraryItem, tags: [String]) {
        do {
            try screenshotLibraryStore.updateTags(id: item.id, tags: tags)
            loadScreenshotLibrary()
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func runBackgroundOCR() {
        guard screenshotFeatureSettings.editorCapabilities.ocr else { return }

        let items = screenshotLibraryItems.filter { $0.recognizedText.isEmpty }
        guard !items.isEmpty else { return }

        showStatus("Running OCR on \(items.count) screenshot\(items.count == 1 ? "" : "s")…")

        DispatchQueue.global(qos: .utility).async {
            for item in items {
                guard let data = try? screenshotLibraryStore.pngData(for: item) else { continue }
                guard let result = try? AtlasBridge.recognizeText(in: data) else { continue }
                try? screenshotLibraryStore.updateText(id: item.id, recognizedText: result.text, translatedText: nil)
            }

            DispatchQueue.main.async {
                loadScreenshotLibrary()
                showStatus("OCR complete")
            }
        }
    }

    private func runBackgroundTranslation() {
        guard screenshotFeatureSettings.editorCapabilities.translation, isTranslationConfigured else { return }

        let items = screenshotLibraryItems.filter { !$0.recognizedText.isEmpty && $0.translatedText.isEmpty }
        guard !items.isEmpty else { return }

        let targetLanguage = translationSettingsDraft.trimmedTargetLanguage
        showStatus("Translating \(items.count) screenshot\(items.count == 1 ? "" : "s")…")

        DispatchQueue.global(qos: .utility).async {
            for item in items {
                guard let result = try? AtlasBridge.translateScreenshotText(item.recognizedText, targetLanguage: targetLanguage) else { continue }
                try? screenshotLibraryStore.updateText(id: item.id, recognizedText: nil, translatedText: result.translatedText)
            }

            DispatchQueue.main.async {
                loadScreenshotLibrary()
                showStatus("Translation complete")
            }
        }
    }

    private func deleteLibraryItem(_ item: ScreenshotLibraryItem) {
        do {
            try screenshotLibraryStore.delete(id: item.id)
            if activeLibraryItemID == item.id {
                closeScreenshotEditor()
            }
            loadScreenshotLibrary()
            showStatus("Deleted screenshot")
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func invalidateScreenshotTextTasks() {
        screenshotTextRevision += 1
        screenshotOCRRevision += 1
        screenshotTranslationRevision += 1
    }

    private func clearScreenshotTextState() {
        recognizedScreenshotText = ""
        isRecognizingScreenshotText = false
        translatedScreenshotText = ""
        isTranslatingScreenshotText = false
    }

    private func copyScreenshot(_ data: Data) {
        annotatedScreenshotData = data
        ScreenshotOutput.copyPNGToClipboard(data, accessLogger: privacyAccessLogger)
        refreshPrivacyPulseIfVisible()
        showStatus("Copied screenshot")
    }

    private func saveScreenshot(_ data: Data) {
        annotatedScreenshotData = data
        if let url = ScreenshotOutput.savePNGWithPanel(data) {
            showStatus("Saved \(url.lastPathComponent)")
        }
    }

    private func copyScreenshotFromThumbnail(_ data: Data) -> FloatingScreenshotThumbnailActionResult {
        copyScreenshot(data)
        return .copied
    }

    private func saveScreenshotFromThumbnail(_ data: Data) -> FloatingScreenshotThumbnailActionResult {
        guard let url = ScreenshotOutput.savePNGWithPanel(data) else {
            showStatus("Save cancelled")
            return .saveCancelled
        }

        showStatus("Saved \(url.lastPathComponent)")
        return .saved(filename: url.lastPathComponent)
    }

    private func dismissFloatingThumbnail() -> FloatingScreenshotThumbnailActionResult {
        showStatus("Dismissed screenshot thumbnail")
        return .dismissed
    }

    private func pinScreenshot(_ data: Data) {
        guard screenshotFeatureSettings.editorCapabilities.pinning else {
            showStatus("Pinning is disabled", kind: .error)
            return
        }

        annotatedScreenshotData = data
        PinnedScreenshotWindow.show(data: data)
        showStatus("Pinned screenshot")
    }

    private func recognizeScreenshotText(_ data: Data) {
        guard screenshotFeatureSettings.editorCapabilities.ocr else {
            showStatus("OCR is disabled", kind: .error)
            return
        }

        screenshotOCRRevision += 1
        screenshotTranslationRevision += 1
        let textRevision = screenshotTextRevision
        let ocrRevision = screenshotOCRRevision

        isRecognizingScreenshotText = true
        recognizedScreenshotText = ""
        translatedScreenshotText = ""
        isTranslatingScreenshotText = false

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try AtlasBridge.recognizeText(in: data) }

            DispatchQueue.main.async {
                guard textRevision == screenshotTextRevision,
                      ocrRevision == screenshotOCRRevision else {
                    return
                }

                isRecognizingScreenshotText = false

                switch result {
                case .success(let ocrResult):
                    recognizedScreenshotText = ocrResult.text
                    updateActiveLibraryItem(recognizedText: ocrResult.text)
                    showStatus(ocrResult.text.isEmpty ? "No text found" : "Recognized text")
                case .failure(let error):
                    showStatus(error.localizedDescription, kind: .error)
                }
            }
        }
    }

    private func copyRecognizedText(_ text: String) {
        copyTextToClipboard(text, detail: "Screenshot OCR copied recognized text to the pasteboard")
        showStatus("Copied recognized text")
    }

    private func translateRecognizedScreenshotText(_ text: String) {
        guard screenshotFeatureSettings.editorCapabilities.translation else {
            showStatus("Translation is disabled", kind: .error)
            return
        }

        screenshotTranslationRevision += 1
        let textRevision = screenshotTextRevision
        let translationRevision = screenshotTranslationRevision
        let sourceText = text

        isTranslatingScreenshotText = true
        translatedScreenshotText = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try AtlasBridge.translateScreenshotText(text, targetLanguage: translationSettingsDraft.trimmedTargetLanguage)
            }

            DispatchQueue.main.async {
                guard textRevision == screenshotTextRevision,
                      translationRevision == screenshotTranslationRevision,
                      recognizedScreenshotText == sourceText else {
                    return
                }

                isTranslatingScreenshotText = false

                switch result {
                case .success(let translationResult):
                    translatedScreenshotText = translationResult.translatedText
                    updateActiveLibraryItem(translatedText: translationResult.translatedText)
                    showStatus("Translated text")
                case .failure(let error):
                    showStatus(error.localizedDescription, kind: .error)
                }
            }
        }
    }

    private func copyTranslatedText(_ text: String) {
        copyTextToClipboard(text, detail: "Screenshot translation copied translated text to the pasteboard")
        showStatus("Copied translated text")
    }

    private func copyTextToClipboard(_ text: String, detail: String) {
        privacyAccessLogger.record(
            category: .clipboard,
            title: "Clipboard Write",
            detail: detail
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        refreshPrivacyPulseIfVisible()
    }

    private func refreshPrivacyPulse() {
        privacyPulseSnapshot = privacyPulseService.snapshot()
    }

    private func refreshPrivacyPulseIfVisible() {
        if isFeatureEnabled(.privacy) {
            refreshPrivacyPulse()
        }
    }

    private func showStatus(
        _ message: String,
        kind: CaptureStatusKind = .success,
        autoHide: Bool = true
    ) {
        statusHideToken += 1
        let token = statusHideToken
        captureStatus = message
        captureStatusKind = kind
        showCaptureStatus = true

        guard autoHide else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard statusHideToken == token else { return }
            showCaptureStatus = false
        }
    }
}

private struct CaptureStatusBanner: View {
    let message: String
    let kind: CaptureStatusKind

    var body: some View {
        HStack {
            Image(systemName: iconName).foregroundColor(color)
            Text(message).font(.caption)
        }
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }

    private var iconName: String {
        switch kind {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .success:
            return .green
        case .error:
            return .red
        }
    }
}

struct CommandPaletteScreenshotLibraryView: View {
    let store: ScreenshotLibraryStore
    let onOpen: (ScreenshotLibraryItem) -> Void
    let onDelete: (ScreenshotLibraryItem) -> Void
    let onRunOCR: (() -> Void)?
    let onRunTranslation: (() -> Void)?
    let onUpdateTags: (ScreenshotLibraryItem, [String]) -> Void
    let onCopyText: (String) -> Void

    @State private var items: [ScreenshotLibraryItem] = []
    @State private var query: String = ""

    var body: some View {
        ScreenshotLibraryPanel(
            items: items,
            onOpen: onOpen,
            onDelete: { item in
                onDelete(item)
                refresh()
            },
            pngURL: { store.pngURL(for: $0) },
            onRunOCR: onRunOCR,
            onRunTranslation: onRunTranslation,
            onUpdateTags: { item, tags in
                onUpdateTags(item, tags)
                refresh()
            },
            onCopyText: onCopyText,
            query: $query
        )
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        items = (try? store.loadItems()) ?? []
    }
}

#Preview {
    ContentView()
}
