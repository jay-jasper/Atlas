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

private enum PrimaryPanelSection: Hashable {
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
    @State private var statusText: String = "Initializing..."
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
    @StateObject private var soundFeedbackService = SoundFeedbackService()
    @StateObject private var keyboardSoundService = KeyboardSoundService()
    @StateObject private var audioMeterService = AudioMeterService()
    @StateObject private var audioRecordingService = AudioRecordingService()
    @State private var isShowingHandMirror = false
    @State private var isShowingSceneEditor = false
    @State private var isShowingSceneDiagnostics = false
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
    private let privacyPulseService: PrivacyPulseService
    private let privacyAccessLogger: PrivacyPulseAccessLogging

    init(
        windowManager: WindowManaging = AccessibilityWindowManager(),
        windowPermissionChecker: WindowManagementPermissionChecking = AccessibilityPermissionChecker(),
        entitlementService: EntitlementService = EntitlementService(provider: LocalEntitlementProvider()),
        paletteState: CommandPaletteState? = nil,
        privacyPulseService: PrivacyPulseService = PrivacyPulseService(
            statusProvider: PrivacyPulseSystemStatusProvider(),
            eventStore: PrivacyPulseAccessLogger()
        ),
        privacyAccessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
    ) {
        let keepAwakeService = KeepAwakeService()
        _keepAwakeService = StateObject(wrappedValue: keepAwakeService)
        _presentationModeService = StateObject(wrappedValue: PresentationModeService(keepAwakeService: keepAwakeService))
        self.windowManager = windowManager
        self.windowPermissionChecker = windowPermissionChecker
        self.entitlementService = entitlementService
        self.paletteState = paletteState
        self.privacyPulseService = privacyPulseService
        self.privacyAccessLogger = privacyAccessLogger
        self.hotkeyService = GlobalHotkeyService(accessLogger: privacyAccessLogger)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(statusText).font(.headline)

                    if showCaptureStatus {
                        CaptureStatusBanner(message: captureStatus, kind: captureStatusKind)
                    }

                    ForEach(orderedPrimarySections(), id: \.self) { section in
                        primaryPanelSection(section)
                    }

                    FeatureCenterPanel(
                        features: features,
                        enabledFeatures: $enabledFeatures,
                        onFeatureChanged: handleFeatureChange
                    )

                    Divider()

                    EditionPanel(state: EditionPanelState(entitlement: entitlementState))

                    Divider()

                    ScreenshotFeatureSettingsPanel(
                        settings: screenshotFeatureSettings,
                        onSave: saveScreenshotFeatureSettings
                    )
                    .id(screenshotFeatureSettingsIdentity)

                    Divider()

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

                    Divider()

                    TranslationSettingsPanel(
                        draft: translationSettingsDraft,
                        isConfigured: isTranslationConfigured,
                        onSave: saveTranslationSettings,
                        onClear: clearTranslationSettings
                    )
                    .id(translationSettingsPanelIdentity)

                    Divider()

                    AppFooter()
                }
                .padding()
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
        .frame(minWidth: 360, minHeight: 500)
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
        .onDisappear(perform: stopModules)
        .onReceive(NotificationCenter.default.publisher(for: .tokenBarSummaryDidChange)) { notification in
            if let summary = notification.object as? TokenBarSummary {
                tokenBarSummary = summary
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tokenBarCommandStatusDidChange)) { notification in
            if let status = notification.object as? TokenBarCommandStatus {
                showStatus(status.message, kind: status.kind == .success ? .success : .error)
            }
        }
    }

    private static let historyMaxCount = 60

    private func startModules() {
        loadScreenshotFeatureSettings()
        loadTranslationSettings()
        loadScreenshotLibrary()
        cleanupScreenshotDragOutput()
        startHotkeys()

        do {
            let loadedFeatures = try AtlasBridge.listFeatures()
            entitlementState = entitlementService.currentState()
            features = entitlementService.applyAvailability(to: loadedFeatures)
            enabledFeatures = FeatureStateReducer.enabledMap(from: loadedFeatures)
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
            statusText = "Atlas is Ready"
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
            statusText = "Atlas feature loading failed"
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
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
        case .colorPicker, .ddcControl, .calendar, .networkMonitor, .appAudio, .fnKey, .totp, .pomodoro, .subtitles, .textExpansion, .hosts, .browserRouter, .envManager, .diskUsage, .proxy, .rss, .quickSwitches, .chapterMarker, .appCleaner, .aspectGuide, .dragShelf, .batteryHealth, .watermark, .obsControl, .teleprompter, .webWallpaper, .keyboardDisplay, .scrollSmoothing, .gifProcessing, .altTab, .colorSampler, .recordingIndicator, .soundFeedback, .keyboardSounds, .audioMeter, .audioRecording:
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
                    onRecordGIF: startGIFRegionSelection
                )

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
