import SwiftUI

private enum CaptureStatusKind {
    case success
    case error
}

struct ContentView: View {
    @State private var statusText: String = "Initializing..."
    @State private var features: [String] = []
    @State private var enabledFeatures: [String: Bool] = [:]
    @State private var snapshot: MonitoringSystemSnapshot? = nil
    @State private var capturedScreenshot: CapturedScreenshot?
    @State private var captureStatus: String = ""
    @State private var captureStatusKind: CaptureStatusKind = .success
    @State private var showCaptureStatus: Bool = false
    @State private var statusHideToken: Int = 0

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
                            onCaptureDesktop: captureDesktop,
                            onCaptureWindow: showWindowSelection,
                            onCaptureArea: showSelectionWindow
                        )

                        Divider()
                    }

                    if isFeatureEnabled(.monitoring) {
                        MonitoringPanel(snapshot: snapshot)

                        Divider()

                        PortMasterPanel()

                        Divider()
                    }

                    FeatureTogglePanel(
                        features: features,
                        enabledFeatures: $enabledFeatures,
                        onFeatureChanged: handleFeatureChange
                    )

                    Divider()

                    AppFooter()
                }
                .padding()
            }

            if let capturedScreenshot {
                ScreenshotEditorView(
                    screenshot: capturedScreenshot,
                    onCopy: copyScreenshot,
                    onSave: saveScreenshot,
                    onPin: pinScreenshot,
                    onClose: { self.capturedScreenshot = nil }
                )
            }
        }
        .frame(minWidth: 360, minHeight: 500)
        .onAppear(perform: startModules)
        .onDisappear(perform: stopModules)
    }

    private func startModules() {
        features = AtlasBridge.listFeatures()
        enabledFeatures = Dictionary(uniqueKeysWithValues: features.map { ($0, true) })
        statusText = "Atlas is Ready"
        if isFeatureEnabled(.monitoring) {
            startMonitoring()
        }
    }

    private func stopModules() {
        AtlasBridge.stopMonitoring()
    }

    private func handleFeatureChange(_ feature: String, enabled: Bool) {
        AtlasBridge.toggleFeature(name: feature, enabled: enabled)

        guard feature == AtlasModule.monitoring.featureName else { return }

        if enabled {
            startMonitoring()
        } else {
            AtlasBridge.stopMonitoring()
            snapshot = nil
        }
    }

    private func startMonitoring() {
        AtlasBridge.startMonitoring { snapshot in
            DispatchQueue.main.async {
                self.snapshot = snapshot
            }
        }
    }

    private func isFeatureEnabled(_ module: AtlasModule) -> Bool {
        enabledFeatures[module.featureName, default: false]
    }

    private func showSelectionWindow() {
        ScreenshotSelectionWindow.show(onCapture: captureSelection)
    }

    private func showWindowSelection() {
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
            capturedScreenshot = CapturedScreenshot(pngData: data, rect: rect)
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
            capturedScreenshot = CapturedScreenshot(pngData: data, rect: pixelRect)
            showStatus("Captured \(bitmap.pixelsWide)×\(bitmap.pixelsHigh) px")
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }

    private func captureDesktop() {
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
        capturedScreenshot = CapturedScreenshot(pngData: data, rect: rect)
        showStatus("Captured full screen")
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
        PinnedScreenshotWindow.show(data: data)
        showStatus("Pinned screenshot")
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
