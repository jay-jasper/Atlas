import SwiftUI

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
    private let screenshotFeatureSettingsStore = ScreenshotFeatureSettingsStore()
    private let translationConfigurationStore = ScreenshotTranslationConfigurationStore()
    private let screenshotLibraryStore = ScreenshotLibraryStore()

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
                        MonitoringPanel(snapshot: snapshot)

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

    private func startModules() {
        loadScreenshotFeatureSettings()
        loadTranslationSettings()
        loadScreenshotLibrary()

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

    private func stopModules() {
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
        clearScreenshotTextState()
    }

    private func loadScreenshotLibrary() {
        do {
            screenshotLibraryItems = try screenshotLibraryStore.loadItems()
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
            onCopy: copyScreenshot,
            onSave: saveScreenshot,
            onDismiss: {}
        )
    }

    private func openFloatingThumbnail(_ screenshot: CapturedScreenshot, libraryItemID: UUID?) {
        invalidateScreenshotTextTasks()
        activeLibraryItemID = libraryItemID
        capturedScreenshot = screenshot
        clearScreenshotTextState()
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
        ScreenshotOutput.copyPNGToClipboard(data)
        showStatus("Copied screenshot")
    }

    private func saveScreenshot(_ data: Data) {
        if let url = ScreenshotOutput.savePNGWithPanel(data) {
            showStatus("Saved \(url.lastPathComponent)")
        }
    }

    private func pinScreenshot(_ data: Data) {
        guard screenshotFeatureSettings.editorCapabilities.pinning else {
            showStatus("Pinning is disabled", kind: .error)
            return
        }

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
                try AtlasBridge.translateScreenshotText(text, targetLanguage: "English")
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

#Preview {
    ContentView()
}
