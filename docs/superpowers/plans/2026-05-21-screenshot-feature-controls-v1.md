# Screenshot Feature Controls v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-screenshot-feature controls so capture modes and editor tools can be enabled or disabled independently while preserving the current default behavior.

**Architecture:** Keep the existing Rust `screenshot` feature as the master module toggle, and add Swift-side subfeature settings for the macOS UI. Persist subfeature settings in `UserDefaults`, pass a small capabilities value into screenshot panels/editor views, and gate only UI entry points in this version.

**Tech Stack:** SwiftUI, AppKit, XCTest, `UserDefaults`, existing Atlas macOS Xcode project.

---

## Scope

This plan implements configurable screenshot subfeatures:

- Desktop capture
- Window capture
- Area capture
- Annotation tools
- Pin screenshot
- OCR
- Translation

Defaults stay enabled for every subfeature, so existing users see the same UI until they turn something off.

Out of scope for this version:

- Rust core feature registration for every screenshot subfeature
- FFI changes
- Keychain or account-based settings
- Per-profile presets
- Manual UI verification
- Removing already implemented screenshot/OCR/translation code

## File Structure

- `platforms/macos/Atlas/ScreenshotFeatureSettings.swift`
  - Owns the screenshot subfeature enum, per-feature labels/icons, immutable settings state, capabilities mapping, and `UserDefaults` store.
- `platforms/macos/Atlas/ScreenshotFeatureSettingsPanel.swift`
  - SwiftUI settings panel with toggles for screenshot subfeatures.
- `platforms/macos/Atlas/ScreenshotPanel.swift`
  - Receives capture capabilities and hides disabled capture buttons.
- `platforms/macos/Atlas/ScreenshotEditorView.swift`
  - Receives editor capabilities and hides disabled editor actions/tools.
- `platforms/macos/Atlas/ContentView.swift`
  - Loads settings, renders the settings panel, passes capabilities into screenshot UI, and guards action handlers.
- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new Swift source and test files to the app/test targets.
- `platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift`
  - Unit tests for defaults, persistence, partial stored values, and capabilities mapping.
- `platforms/macos/AtlasTests/ScreenshotFeatureSettingsPanelTests.swift`
  - Unit tests for panel state summary/count behavior without relying on visual inspection.

---

### Task 1: Screenshot Feature Settings Model and Store

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotFeatureSettings.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing tests for defaults and persistence**

Create `platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScreenshotFeatureSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ScreenshotFeatureSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultSettingsEnableEveryScreenshotFeature() {
        let settings = ScreenshotFeatureSettings.defaultEnabled

        XCTAssertTrue(settings.isEnabled(.desktopCapture))
        XCTAssertTrue(settings.isEnabled(.windowCapture))
        XCTAssertTrue(settings.isEnabled(.areaCapture))
        XCTAssertTrue(settings.isEnabled(.annotations))
        XCTAssertTrue(settings.isEnabled(.pinning))
        XCTAssertTrue(settings.isEnabled(.ocr))
        XCTAssertTrue(settings.isEnabled(.translation))
        XCTAssertEqual(settings.enabledCount, ScreenshotSubfeature.allCases.count)
    }

    func testStoreReturnsDefaultsWhenNothingWasSaved() {
        let store = ScreenshotFeatureSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .defaultEnabled)
    }

    func testStoreSavesAndLoadsDisabledFeatures() {
        let store = ScreenshotFeatureSettingsStore(defaults: defaults)
        var settings = ScreenshotFeatureSettings.defaultEnabled
        settings.setEnabled(false, for: .windowCapture)
        settings.setEnabled(false, for: .translation)

        store.save(settings)

        let loaded = store.load()
        XCTAssertFalse(loaded.isEnabled(.windowCapture))
        XCTAssertFalse(loaded.isEnabled(.translation))
        XCTAssertTrue(loaded.isEnabled(.desktopCapture))
        XCTAssertTrue(loaded.isEnabled(.ocr))
    }

    func testStoreTreatsMissingFeatureKeysAsEnabled() {
        defaults.set(false, forKey: "screenshot.subfeature.ocr.enabled")

        let loaded = ScreenshotFeatureSettingsStore(defaults: defaults).load()

        XCTAssertFalse(loaded.isEnabled(.ocr))
        XCTAssertTrue(loaded.isEnabled(.desktopCapture))
        XCTAssertTrue(loaded.isEnabled(.windowCapture))
        XCTAssertTrue(loaded.isEnabled(.areaCapture))
        XCTAssertTrue(loaded.isEnabled(.annotations))
        XCTAssertTrue(loaded.isEnabled(.pinning))
        XCTAssertTrue(loaded.isEnabled(.translation))
    }

    func testCapabilitiesMapSettingsToCaptureAndEditorSurfaces() {
        var settings = ScreenshotFeatureSettings.defaultEnabled
        settings.setEnabled(false, for: .areaCapture)
        settings.setEnabled(false, for: .annotations)
        settings.setEnabled(false, for: .pinning)
        settings.setEnabled(false, for: .translation)

        XCTAssertTrue(settings.captureCapabilities.desktop)
        XCTAssertTrue(settings.captureCapabilities.window)
        XCTAssertFalse(settings.captureCapabilities.area)
        XCTAssertFalse(settings.editorCapabilities.annotations)
        XCTAssertFalse(settings.editorCapabilities.pinning)
        XCTAssertTrue(settings.editorCapabilities.ocr)
        XCTAssertFalse(settings.editorCapabilities.translation)
    }

    func testFeatureMetadataIsStable() {
        XCTAssertEqual(ScreenshotSubfeature.allCases.map(\\.rawValue), [
            "desktop-capture",
            "window-capture",
            "area-capture",
            "annotations",
            "pinning",
            "ocr",
            "translation",
        ])

        XCTAssertEqual(ScreenshotSubfeature.desktopCapture.title, "Desktop Capture")
        XCTAssertEqual(ScreenshotSubfeature.windowCapture.systemImage, "macwindow")
        XCTAssertEqual(ScreenshotSubfeature.translation.title, "Translation")
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests
```

Expected: FAIL because `ScreenshotFeatureSettingsTests.swift` is not yet in the project and the referenced types do not exist.

- [x] **Step 3: Add settings implementation**

Create `platforms/macos/Atlas/ScreenshotFeatureSettings.swift`:

```swift
import Foundation

enum ScreenshotSubfeature: String, CaseIterable, Identifiable {
    case desktopCapture = "desktop-capture"
    case windowCapture = "window-capture"
    case areaCapture = "area-capture"
    case annotations
    case pinning
    case ocr
    case translation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktopCapture:
            return "Desktop Capture"
        case .windowCapture:
            return "Window Capture"
        case .areaCapture:
            return "Area Capture"
        case .annotations:
            return "Annotations"
        case .pinning:
            return "Pinning"
        case .ocr:
            return "OCR"
        case .translation:
            return "Translation"
        }
    }

    var detail: String {
        switch self {
        case .desktopCapture:
            return "Capture the full desktop."
        case .windowCapture:
            return "Capture a selected application window."
        case .areaCapture:
            return "Capture a selected screen region."
        case .annotations:
            return "Show rectangle, arrow, pen, text, and pixelate tools."
        case .pinning:
            return "Pin screenshots in a floating window."
        case .ocr:
            return "Recognize text from screenshots."
        case .translation:
            return "Translate recognized screenshot text."
        }
    }

    var systemImage: String {
        switch self {
        case .desktopCapture:
            return "display"
        case .windowCapture:
            return "macwindow"
        case .areaCapture:
            return "selection.pin.in.out"
        case .annotations:
            return "pencil.and.outline"
        case .pinning:
            return "pin"
        case .ocr:
            return "text.viewfinder"
        case .translation:
            return "globe"
        }
    }
}

struct ScreenshotCaptureCapabilities: Equatable {
    var desktop: Bool
    var window: Bool
    var area: Bool

    static let allEnabled = ScreenshotCaptureCapabilities(desktop: true, window: true, area: true)
}

struct ScreenshotEditorCapabilities: Equatable {
    var annotations: Bool
    var pinning: Bool
    var ocr: Bool
    var translation: Bool

    static let allEnabled = ScreenshotEditorCapabilities(
        annotations: true,
        pinning: true,
        ocr: true,
        translation: true
    )
}

struct ScreenshotFeatureSettings: Equatable {
    private var enabledByFeature: [ScreenshotSubfeature: Bool]

    static let defaultEnabled = ScreenshotFeatureSettings(
        enabledByFeature: Dictionary(
            uniqueKeysWithValues: ScreenshotSubfeature.allCases.map { ($0, true) }
        )
    )

    init(enabledByFeature: [ScreenshotSubfeature: Bool]) {
        self.enabledByFeature = enabledByFeature
    }

    func isEnabled(_ feature: ScreenshotSubfeature) -> Bool {
        enabledByFeature[feature, default: true]
    }

    mutating func setEnabled(_ enabled: Bool, for feature: ScreenshotSubfeature) {
        enabledByFeature[feature] = enabled
    }

    var enabledCount: Int {
        ScreenshotSubfeature.allCases.filter { isEnabled($0) }.count
    }

    var captureCapabilities: ScreenshotCaptureCapabilities {
        ScreenshotCaptureCapabilities(
            desktop: isEnabled(.desktopCapture),
            window: isEnabled(.windowCapture),
            area: isEnabled(.areaCapture)
        )
    }

    var editorCapabilities: ScreenshotEditorCapabilities {
        ScreenshotEditorCapabilities(
            annotations: isEnabled(.annotations),
            pinning: isEnabled(.pinning),
            ocr: isEnabled(.ocr),
            translation: isEnabled(.translation)
        )
    }
}

struct ScreenshotFeatureSettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ScreenshotFeatureSettings {
        var settings = ScreenshotFeatureSettings.defaultEnabled

        for feature in ScreenshotSubfeature.allCases {
            let key = defaultsKey(for: feature)
            if defaults.object(forKey: key) != nil {
                settings.setEnabled(defaults.bool(forKey: key), for: feature)
            }
        }

        return settings
    }

    func save(_ settings: ScreenshotFeatureSettings) {
        for feature in ScreenshotSubfeature.allCases {
            defaults.set(settings.isEnabled(feature), forKey: defaultsKey(for: feature))
        }
    }

    private func defaultsKey(for feature: ScreenshotSubfeature) -> String {
        "screenshot.subfeature.\(feature.rawValue).enabled"
    }
}
```

- [x] **Step 4: Add files to Xcode project**

Modify `platforms/macos/Atlas.xcodeproj/project.pbxproj` using the existing PBX patterns in the file:

- Add `ScreenshotFeatureSettings.swift` to the `Atlas` group and app target `Sources`.
- Add `ScreenshotFeatureSettingsTests.swift` to the `AtlasTests` group and test target `Sources`.
- Use new unique 24-character hex IDs with the same formatting as adjacent entries.

Do not change build settings or reorder unrelated project entries.

- [x] **Step 5: Run tests to verify settings pass**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests
```

Expected: PASS with 6 tests.

- [x] **Step 6: Commit settings model**

```bash
git add platforms/macos/Atlas/ScreenshotFeatureSettings.swift platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add screenshot feature settings"
```

---

### Task 2: Screenshot Feature Settings Panel

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotFeatureSettingsPanel.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotFeatureSettingsPanelTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing tests for panel state**

Create `platforms/macos/AtlasTests/ScreenshotFeatureSettingsPanelTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScreenshotFeatureSettingsPanelTests: XCTestCase {
    func testStateSummaryForAllEnabledSettings() {
        let state = ScreenshotFeatureSettingsPanelState(settings: .defaultEnabled)

        XCTAssertEqual(state.enabledCount, ScreenshotSubfeature.allCases.count)
        XCTAssertEqual(state.totalCount, ScreenshotSubfeature.allCases.count)
        XCTAssertEqual(state.summaryText, "7 enabled")
        XCTAssertFalse(state.hasDisabledFeatures)
    }

    func testStateSummaryForPartiallyDisabledSettings() {
        var settings = ScreenshotFeatureSettings.defaultEnabled
        settings.setEnabled(false, for: .ocr)
        settings.setEnabled(false, for: .translation)

        let state = ScreenshotFeatureSettingsPanelState(settings: settings)

        XCTAssertEqual(state.enabledCount, 5)
        XCTAssertEqual(state.totalCount, 7)
        XCTAssertEqual(state.summaryText, "5 of 7 enabled")
        XCTAssertTrue(state.hasDisabledFeatures)
    }

    func testBindingUpdateChangesOnlySelectedFeature() {
        var settings = ScreenshotFeatureSettings.defaultEnabled

        ScreenshotFeatureSettingsPanelState.set(false, for: .windowCapture, in: &settings)

        XCTAssertFalse(settings.isEnabled(.windowCapture))
        XCTAssertTrue(settings.isEnabled(.desktopCapture))
        XCTAssertTrue(settings.isEnabled(.areaCapture))
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsPanelTests
```

Expected: FAIL because `ScreenshotFeatureSettingsPanelState` and `ScreenshotFeatureSettingsPanel` do not exist.

- [x] **Step 3: Add panel implementation**

Create `platforms/macos/Atlas/ScreenshotFeatureSettingsPanel.swift`:

```swift
import SwiftUI

struct ScreenshotFeatureSettingsPanelState: Equatable {
    let settings: ScreenshotFeatureSettings

    var enabledCount: Int {
        settings.enabledCount
    }

    var totalCount: Int {
        ScreenshotSubfeature.allCases.count
    }

    var summaryText: String {
        if enabledCount == totalCount {
            return "\(enabledCount) enabled"
        }
        return "\(enabledCount) of \(totalCount) enabled"
    }

    var hasDisabledFeatures: Bool {
        enabledCount < totalCount
    }

    static func set(
        _ enabled: Bool,
        for feature: ScreenshotSubfeature,
        in settings: inout ScreenshotFeatureSettings
    ) {
        settings.setEnabled(enabled, for: feature)
    }
}

struct ScreenshotFeatureSettingsPanel: View {
    @State private var draft: ScreenshotFeatureSettings

    let onSave: (ScreenshotFeatureSettings) -> Void

    init(settings: ScreenshotFeatureSettings, onSave: @escaping (ScreenshotFeatureSettings) -> Void) {
        _draft = State(initialValue: settings)
        self.onSave = onSave
    }

    var body: some View {
        let state = ScreenshotFeatureSettingsPanelState(settings: draft)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Screenshot Features")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(state.summaryText)
                    .font(.caption)
                    .foregroundColor(state.hasDisabledFeatures ? .orange : .secondary)
            }

            ForEach(ScreenshotSubfeature.allCases) { feature in
                Toggle(isOn: binding(for: feature)) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: feature.systemImage)
                            .frame(width: 18)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                            Text(feature.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Save") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func binding(for feature: ScreenshotSubfeature) -> Binding<Bool> {
        Binding(
            get: { draft.isEnabled(feature) },
            set: { enabled in
                ScreenshotFeatureSettingsPanelState.set(enabled, for: feature, in: &draft)
            }
        )
    }
}
```

- [x] **Step 4: Add files to Xcode project**

Modify `platforms/macos/Atlas.xcodeproj/project.pbxproj`:

- Add `ScreenshotFeatureSettingsPanel.swift` to the `Atlas` group and app target `Sources`.
- Add `ScreenshotFeatureSettingsPanelTests.swift` to the `AtlasTests` group and test target `Sources`.
- Use new unique 24-character hex IDs with the same formatting as adjacent entries.

- [x] **Step 5: Run focused panel tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsPanelTests
```

Expected: PASS with 3 tests.

- [x] **Step 6: Commit panel**

```bash
git add platforms/macos/Atlas/ScreenshotFeatureSettingsPanel.swift platforms/macos/AtlasTests/ScreenshotFeatureSettingsPanelTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add screenshot feature settings panel"
```

---

### Task 3: Gate Screenshot Capture and Editor UI

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotPanel.swift`
- Modify: `platforms/macos/Atlas/ScreenshotEditorView.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [x] **Step 1: Update `ScreenshotPanel` to hide disabled capture buttons**

Modify `platforms/macos/Atlas/ScreenshotPanel.swift` to this full implementation:

```swift
import SwiftUI

struct ScreenshotPanel: View {
    let capabilities: ScreenshotCaptureCapabilities
    let onCaptureDesktop: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureArea: () -> Void

    var body: some View {
        Group {
            Text("Screenshot").font(.subheadline).foregroundColor(.secondary)
            HStack {
                if capabilities.desktop {
                    captureButton(for: .desktop, action: onCaptureDesktop, prominent: true)
                }
                if capabilities.window {
                    captureButton(for: .window, action: onCaptureWindow, prominent: !capabilities.desktop)
                }
                if capabilities.area {
                    captureButton(
                        for: .area,
                        action: onCaptureArea,
                        prominent: !capabilities.desktop && !capabilities.window
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func captureButton(
        for mode: ScreenshotCaptureMode,
        action: @escaping () -> Void,
        prominent: Bool
    ) -> some View {
        if prominent {
            Button(action: action) {
                Label(mode.title, systemImage: mode.systemImage)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) {
                Label(mode.title, systemImage: mode.systemImage)
            }
            .buttonStyle(.bordered)
        }
    }
}
```

- [x] **Step 2: Update `ScreenshotEditorView` to accept editor capabilities**

Modify `platforms/macos/Atlas/ScreenshotEditorView.swift`:

1. Add a stored property near `screenshot`:

```swift
let capabilities: ScreenshotEditorCapabilities
```

2. Change the toolbar tool loop so annotation tools are hidden when annotations are disabled:

```swift
if capabilities.annotations {
    ForEach(ScreenshotTool.allCases) { tool in
        Button {
            selectedTool = tool
        } label: {
            Image(systemName: tool.systemImage)
        }
        .help(tool.title)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .background(selectedTool == tool ? Color.accentColor.opacity(0.18) : Color.clear)
        .cornerRadius(6)
    }
}
```

3. Change `outputBar` buttons so Pin and OCR are gated:

```swift
private var outputBar: some View {
    HStack {
        Button("Copy") { onCopy(renderedData()) }
        Button("Save") { onSave(renderedData()) }
        if capabilities.pinning {
            Button("Pin") { onPin(renderedData()) }
        }
        if capabilities.ocr {
            Button("OCR") { onRecognizeText(renderedData()) }
                .disabled(isRecognizingText)
        }
        Spacer()
        if isRecognizingText {
            ProgressView()
                .controlSize(.small)
        }
        Text("\(Int(screenshot.rect.width)) x \(Int(screenshot.rect.height))")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding(10)
}
```

4. Change the recognized text panel so translation is gated:

```swift
if capabilities.translation {
    if isTranslatingText {
        ProgressView()
            .controlSize(.small)
    }
    Button("Translate") { onTranslateRecognizedText(recognizedText) }
        .controlSize(.small)
        .disabled(isTranslatingText)
}
```

5. Change `annotationDrag` to ignore annotation input when annotations are disabled:

```swift
private var annotationDrag: some Gesture {
    DragGesture(minimumDistance: 0)
        .onChanged { value in
            guard capabilities.annotations else { return }
            if dragStart == nil {
                dragStart = value.startLocation
            }
        }
        .onEnded { value in
            guard capabilities.annotations else { return }
            guard let start = dragStart else { return }
            let rect = CGRect(
                x: min(start.x, value.location.x),
                y: min(start.y, value.location.y),
                width: abs(start.x - value.location.x),
                height: abs(start.y - value.location.y)
            ).integral

            switch selectedTool {
            case .rectangle:
                annotations.append(.rectangle(rect: rect, color: .red, lineWidth: 2))
            case .arrow:
                annotations.append(.arrow(from: start, to: value.location, color: .red, lineWidth: 2))
            case .pen:
                annotations.append(.pen(points: [start, value.location], color: .red, lineWidth: 2))
            case .text:
                annotations.append(.text(value: "Text", rect: rect.width > 8 && rect.height > 8 ? rect : CGRect(x: start.x, y: start.y, width: 80, height: 28), color: .red))
            case .pixelate:
                annotations.append(.pixelate(rect: rect))
            }

            dragStart = nil
        }
}
```

- [x] **Step 3: Wire settings into `ContentView`**

Modify `platforms/macos/Atlas/ContentView.swift`:

1. Add state and store near translation settings state:

```swift
@State private var screenshotFeatureSettings: ScreenshotFeatureSettings = .defaultEnabled
private let screenshotFeatureSettingsStore = ScreenshotFeatureSettingsStore()
```

2. Pass capture capabilities into `ScreenshotPanel`:

```swift
ScreenshotPanel(
    capabilities: screenshotFeatureSettings.captureCapabilities,
    onCaptureDesktop: captureDesktop,
    onCaptureWindow: showWindowSelection,
    onCaptureArea: showSelectionWindow
)
```

3. Pass editor capabilities into `ScreenshotEditorView`:

```swift
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
```

4. Render `ScreenshotFeatureSettingsPanel` after `FeatureCenterPanel` and before `TranslationSettingsPanel`:

```swift
ScreenshotFeatureSettingsPanel(
    settings: screenshotFeatureSettings,
    onSave: saveScreenshotFeatureSettings
)
.id(screenshotFeatureSettingsIdentity)

Divider()
```

5. Load screenshot settings in `startModules()` before feature loading:

```swift
loadScreenshotFeatureSettings()
loadTranslationSettings()
```

6. Add helper methods:

```swift
private var screenshotFeatureSettingsIdentity: String {
    ScreenshotSubfeature.allCases
        .map { screenshotFeatureSettings.isEnabled($0) ? "1" : "0" }
        .joined(separator: "")
}

private func loadScreenshotFeatureSettings() {
    screenshotFeatureSettings = screenshotFeatureSettingsStore.load()
}

private func saveScreenshotFeatureSettings(_ settings: ScreenshotFeatureSettings) {
    screenshotFeatureSettingsStore.save(settings)
    loadScreenshotFeatureSettings()
    showStatus("Screenshot feature settings saved")
}
```

7. Guard disabled capture actions:

```swift
private func showSelectionWindow() {
    guard screenshotFeatureSettings.captureCapabilities.area else {
        showStatus("Area capture is disabled", kind: .error)
        return
    }

    let previewImageData = selectionPreviewImageData()
    ScreenshotSelectionWindow.show(previewImageData: previewImageData, onCapture: captureSelection)
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
    setCapturedScreenshot(CapturedScreenshot(pngData: data, rect: rect))
    showStatus("Captured full screen")
}
```

8. Guard disabled editor actions:

```swift
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
                showStatus(ocrResult.text.isEmpty ? "No text found" : "Recognized text")
            case .failure(let error):
                showStatus(error.localizedDescription, kind: .error)
            }
        }
    }
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
                showStatus("Translated text")
            case .failure(let error):
                showStatus(error.localizedDescription, kind: .error)
            }
        }
    }
}
```

- [x] **Step 4: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [x] **Step 5: Run focused screenshot feature tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests -only-testing:AtlasTests/ScreenshotFeatureSettingsPanelTests
```

Expected: PASS with 9 tests.

- [x] **Step 6: Commit UI gating**

```bash
git add platforms/macos/Atlas/ScreenshotPanel.swift platforms/macos/Atlas/ScreenshotEditorView.swift platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): gate screenshot UI by feature settings"
```

---

### Task 4: Final Verification and Plan Notes

**Files:**
- Modify: `docs/superpowers/plans/2026-05-21-screenshot-feature-controls-v1.md`

- [x] **Step 1: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [x] **Step 2: Run focused screenshot feature tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests -only-testing:AtlasTests/ScreenshotFeatureSettingsPanelTests
```

Expected: PASS.

- [x] **Step 3: Run full macOS tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected: PASS. The existing CoreSimulator out-of-date warning is acceptable if macOS tests run and `TEST SUCCEEDED` appears.

- [x] **Step 4: Run Rust core tests**

Run:

```bash
cargo test -p atlas-core
```

Expected: PASS.

- [x] **Step 5: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-21-screenshot-feature-controls-v1.md`:

```markdown
---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
- Focused screenshot feature tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests -only-testing:AtlasTests/ScreenshotFeatureSettingsPanelTests`
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Rust core tests: `cargo test -p atlas-core`

Screenshot Feature Controls v1 intentionally keeps subfeature gating in the macOS UI layer. The Rust `screenshot` feature remains the master module toggle, and all subfeatures default to enabled to preserve current behavior.
```

- [x] **Step 6: Commit verification notes**

```bash
git add docs/superpowers/plans/2026-05-21-screenshot-feature-controls-v1.md
git commit -m "docs: record screenshot feature controls v1 verification"
```

---

## Self-Review

1. **Spec coverage:** The plan covers configurable screenshot subfeatures, separates settings from capture/editor UI, preserves current behavior through enabled defaults, and avoids Rust/FFI expansion that is outside this UI-level feature controls version.
2. **Placeholder scan:** No task uses incomplete placeholder instructions. Each new file has concrete test or implementation content, and each command has an expected result.
3. **Type consistency:** `ScreenshotSubfeature`, `ScreenshotFeatureSettings`, `ScreenshotCaptureCapabilities`, `ScreenshotEditorCapabilities`, `ScreenshotFeatureSettingsStore`, `ScreenshotFeatureSettingsPanelState`, and `ScreenshotFeatureSettingsPanel` are defined before later tasks use them.

---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift` passed with no output.
- Focused screenshot feature tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests -only-testing:AtlasTests/ScreenshotFeatureSettingsPanelTests` passed with 9 tests.
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'` passed with 101 tests. Xcode emitted the existing CoreSimulator out-of-date warning, but macOS tests ran and `TEST SUCCEEDED` appeared.
- Rust core tests: `cargo test -p atlas-core` passed with 21 tests.

Screenshot Feature Controls v1 intentionally keeps subfeature gating in the macOS UI layer. The Rust `screenshot` feature remains the master module toggle, and all subfeatures default to enabled to preserve current behavior.
