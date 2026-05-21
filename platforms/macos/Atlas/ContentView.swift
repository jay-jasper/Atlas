import SwiftUI
import UniformTypeIdentifiers

private enum CaptureStatusKind {
    case success
    case error
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
    @State private var cpuHistory: [Double] = []
    @State private var memoryHistory: [Double] = []
    private let screenshotFeatureSettingsStore = ScreenshotFeatureSettingsStore()
    private let translationConfigurationStore = ScreenshotTranslationConfigurationStore()
    private let screenshotLibraryStore = ScreenshotLibraryStore()
    private let screenshotDragOutputStore = ScreenshotDragOutputStore()
    private let hotkeyService = GlobalHotkeyService()
    var paletteState: CommandPaletteState? = nil

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(statusText).font(.headline)

                    if showCaptureStatus {
                        CaptureStatusBanner(message: captureStatus, kind: captureStatusKind)
                    }

                    Divider()

                    if isFeatureEnabled(.screenshot) {
                        ScreenshotPanel(
                            capabilities: screenshotFeatureSettings.captureCapabilities,
                            onCaptureDesktop: captureDesktop,
                            onCaptureWindow: showWindowSelection,
                            onCaptureArea: showSelectionWindow
                        )

                        Divider()
                    }

                    if isFeatureEnabled(.monitoring) {
                        MonitoringPanel(
                            snapshot: snapshot,
                            cpuHistory: cpuHistory,
                            memoryHistory: memoryHistory
                        )

                        Divider()
                    }

                    FeatureCenterPanel(
                        features: features,
                        enabledFeatures: $enabledFeatures,
                        onFeatureChanged: handleFeatureChange
                    )

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
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
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
        .onAppear(perform: startModules)
        .onDisappear(perform: stopModules)
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
            features = loadedFeatures
            enabledFeatures = FeatureStateReducer.enabledMap(from: loadedFeatures)
            statusText = "Atlas is Ready"
            if isFeatureEnabled(.monitoring) {
                startMonitoring()
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
            onCaptureWindow: { self.showWindowSelection() }
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
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
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
        }
    }

    private func stopModules() {
        hotkeyService.stop()
        do {
            try AtlasBridge.stopMonitoring()
        } catch {
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
        }
    }

    private func handleFeatureChange(_ feature: String, enabled: Bool) {
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
        features = FeatureStateReducer.refreshedFeatures(features, featureName: feature, enabled: enabled)

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

    private func isFeatureEnabled(_ module: AtlasModule) -> Bool {
        enabledFeatures[module.featureName, default: false]
    }

    private func showSelectionWindow() {
        guard screenshotFeatureSettings.captureCapabilities.area else {
            showStatus("Area capture is disabled", kind: .error)
            return
        }

        let previewImageData = selectionPreviewImageData()
        ScreenshotSelectionWindow.show(previewImageData: previewImageData, onCapture: captureSelection)
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

    private func setCapturedScreenshot(_ screenshot: CapturedScreenshot, source: String) {
        invalidateScreenshotTextTasks()
        clearScreenshotTextState()
        capturedScreenshot = nil
        let libraryItemID = recordScreenshotInLibrary(screenshot, source: source)
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
        ScreenshotOutput.copyPNGToClipboard(data)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showStatus("Copied translated text")
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
