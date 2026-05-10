import SwiftUI

struct ContentView: View {
    @State private var statusText: String = "Initializing..."
    @State private var features: [String] = []
    @State private var enabledFeatures: [String: Bool] = [:]
    @State private var snapshot: SystemSnapshot? = nil
    @State private var isShowingSelectionOverlay: Bool = false
    @State private var capturedScreenshot: CapturedScreenshot?
    @State private var captureStatus: String = ""
    @State private var showCaptureStatus: Bool = false
    @State private var statusHideToken: Int = 0

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(statusText).font(.headline)

                    if showCaptureStatus {
                        CaptureStatusBanner(message: captureStatus)
                    }

                    Divider()

                    if isFeatureEnabled(.screenshot) {
                        ScreenshotPanel {
                            isShowingSelectionOverlay = true
                        }

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

            if isShowingSelectionOverlay {
                SelectionOverlay(
                    onCancel: { isShowingSelectionOverlay = false },
                    onCapture: captureSelection
                )
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

    private func captureSelection(_ rect: CGRect) {
        if let data = AtlasBridge.captureRegion(
            x: Int32(rect.minX),
            y: Int32(rect.minY),
            width: UInt32(rect.width),
            height: UInt32(rect.height)
        ) {
            capturedScreenshot = CapturedScreenshot(pngData: data, rect: rect)
            showStatus("Captured \(Int(rect.width))×\(Int(rect.height)) px")
        }
        isShowingSelectionOverlay = false
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

    private func showStatus(_ message: String, autoHide: Bool = true) {
        statusHideToken += 1
        let token = statusHideToken
        captureStatus = message
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

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text(message).font(.caption)
        }
        .padding(8)
        .background(Color.green.opacity(0.1))
        .cornerRadius(6)
    }
}

#Preview {
    ContentView()
}
