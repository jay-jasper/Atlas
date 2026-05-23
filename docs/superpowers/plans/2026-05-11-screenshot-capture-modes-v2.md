# Screenshot Capture Modes v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three explicit screenshot entry points: whole desktop, selected window, and selected area.

**Architecture:** Keep desktop and area capture on the existing Rust UniFFI path. Add selected-window capture as a macOS-native CoreGraphics adapter behind the same Swift capture boundary, because window enumeration and click/selection UX are platform UI concerns. The UI exposes three independent modes so each mode can later be feature-gated or disabled without touching the others.

**Tech Stack:** SwiftUI, AppKit, CoreGraphics, XCTest, existing Rust/UniFFI capture APIs.

---

## Scope Check

This plan covers only screenshot capture modes:

- Rename the current full-screen action to whole desktop in UI and code.
- Keep selected area capture using the existing overlay and coordinate mapper.
- Add selected window capture with window enumeration, a picker, and CoreGraphics window image capture.
- Keep tests deterministic by injecting fake window capture providers.
- Do not implement OCR, translation, scrolling capture, multi-display stitching, or monitoring/port changes.

Known limitation: the existing Rust `CaptureEngine::capture_full_screen()` still captures the first screen, not all displays. This plan labels that behavior clearly as `Desktop` in the UI and records the limitation. A later plan can replace it with multi-display desktop stitching.

## File Structure

- Create: `platforms/macos/Atlas/ScreenshotCaptureMode.swift`
  - Defines the three modes and their UI labels/icons.
- Modify: `platforms/macos/Atlas/ScreenshotPanel.swift`
  - Shows `Desktop`, `Window`, and `Area` buttons with separate callbacks.
- Modify: `platforms/macos/Atlas/ContentView.swift`
  - Wires the three actions into the app.
  - Renames full-screen handler to desktop handler.
  - Opens the window picker for selected-window capture.
- Create: `platforms/macos/Atlas/WindowCaptureService.swift`
  - Defines `CapturableWindow`, `WindowCaptureProviding`, `CoreGraphicsWindowCaptureProvider`, and `WindowCaptureError`.
- Create: `platforms/macos/Atlas/WindowSelectionWindow.swift`
  - Presents a small SwiftUI/AppKit picker for selecting one visible window.
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
  - Adds injectable `windowCaptureProvider`, `listCapturableWindows()`, and `captureWindow(id:)`.
  - Keeps desktop/area capture on `AtlasCaptureService`.
- Test: `platforms/macos/AtlasTests/WindowCaptureServiceTests.swift`
  - Tests bridge injection and error propagation without using real Screen Recording.
- Test: `platforms/macos/AtlasTests/ScreenshotCaptureModeTests.swift`
  - Tests mode labels and SF Symbol names.
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new source and test files to the correct targets.
- Modify: `docs/superpowers/plans/2026-05-10-uniffi-real-capture.md`
  - Adds a short follow-up note that full-screen was renamed to desktop mode and still has a primary-display limitation.

---

### Task 1: Capture Mode Model

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotCaptureMode.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotCaptureModeTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Write the mode tests**

Create `platforms/macos/AtlasTests/ScreenshotCaptureModeTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScreenshotCaptureModeTests: XCTestCase {
    func testModesHaveStableOrder() {
        XCTAssertEqual(ScreenshotCaptureMode.allCases, [.desktop, .window, .area])
    }

    func testModeLabels() {
        XCTAssertEqual(ScreenshotCaptureMode.desktop.title, "Desktop")
        XCTAssertEqual(ScreenshotCaptureMode.window.title, "Window")
        XCTAssertEqual(ScreenshotCaptureMode.area.title, "Area")
    }

    func testModeSymbols() {
        XCTAssertEqual(ScreenshotCaptureMode.desktop.systemImage, "display")
        XCTAssertEqual(ScreenshotCaptureMode.window.systemImage, "macwindow")
        XCTAssertEqual(ScreenshotCaptureMode.area.systemImage, "selection.pin.in.out")
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotCaptureModeTests
```

Expected: FAIL because `ScreenshotCaptureMode` does not exist or the test file is not in the project yet.

- [x] **Step 3: Add the mode model**

Create `platforms/macos/Atlas/ScreenshotCaptureMode.swift`:

```swift
enum ScreenshotCaptureMode: String, CaseIterable, Equatable {
    case desktop
    case window
    case area

    var title: String {
        switch self {
        case .desktop:
            return "Desktop"
        case .window:
            return "Window"
        case .area:
            return "Area"
        }
    }

    var systemImage: String {
        switch self {
        case .desktop:
            return "display"
        case .window:
            return "macwindow"
        case .area:
            return "selection.pin.in.out"
        }
    }
}
```

- [x] **Step 4: Add files to the Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so:

- `ScreenshotCaptureMode.swift` is in the `Atlas` target Sources build phase.
- `ScreenshotCaptureModeTests.swift` is in the `AtlasTests` target Sources build phase.
- Use deterministic `83CBBA...` IDs consistent with the existing project.

- [x] **Step 5: Run the mode tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotCaptureModeTests
```

Expected: PASS, 3 tests.

- [x] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotCaptureMode.swift \
  platforms/macos/AtlasTests/ScreenshotCaptureModeTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add screenshot capture modes"
```

---

### Task 2: Three-Mode Screenshot Panel

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotPanel.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [x] **Step 1: Update `ScreenshotPanel` API**

Replace `platforms/macos/Atlas/ScreenshotPanel.swift` with:

```swift
import SwiftUI

struct ScreenshotPanel: View {
    let onCaptureDesktop: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureArea: () -> Void

    var body: some View {
        Group {
            Text("Screenshot").font(.subheadline).foregroundColor(.secondary)
            HStack {
                captureButton(for: .desktop, action: onCaptureDesktop, prominent: true)
                captureButton(for: .window, action: onCaptureWindow, prominent: false)
                captureButton(for: .area, action: onCaptureArea, prominent: false)
            }
        }
    }

    private func captureButton(
        for mode: ScreenshotCaptureMode,
        action: @escaping () -> Void,
        prominent: Bool
    ) -> some View {
        Button(action: action) {
            Label(mode.title, systemImage: mode.systemImage)
        }
        .buttonStyle(prominent ? .borderedProminent : .bordered)
    }
}
```

- [x] **Step 2: Update `ContentView` call site**

In `platforms/macos/Atlas/ContentView.swift`, replace:

```swift
ScreenshotPanel(
    onSelectArea: showSelectionWindow,
    onFullScreen: captureFullScreen
)
```

with:

```swift
ScreenshotPanel(
    onCaptureDesktop: captureDesktop,
    onCaptureWindow: showWindowSelection,
    onCaptureArea: showSelectionWindow
)
```

Then rename:

```swift
private func captureFullScreen() {
```

to:

```swift
private func captureDesktop() {
```

Keep the method body unchanged for this task. Add this placeholder method below `showSelectionWindow()`:

```swift
private func showWindowSelection() {
    showStatus("Window capture is not available yet", kind: .error)
}
```

- [x] **Step 3: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [x] **Step 4: Build app**

Run:

```bash
xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [x] **Step 5: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotPanel.swift platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): expose desktop window area screenshot actions"
```

---

### Task 3: Window Capture Service

**Files:**
- Create: `platforms/macos/Atlas/WindowCaptureService.swift`
- Create: `platforms/macos/AtlasTests/WindowCaptureServiceTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Write bridge-injection tests**

Create `platforms/macos/AtlasTests/WindowCaptureServiceTests.swift`:

```swift
import CoreGraphics
import Foundation
import XCTest
@testable import Atlas

private final class FakeWindowCaptureProvider: WindowCaptureProviding {
    var windows: [CapturableWindow] = [
        CapturableWindow(id: 42, title: "Spec", ownerName: "Atlas", bounds: CGRect(x: 1, y: 2, width: 300, height: 200))
    ]
    var capturedWindowID: CGWindowID?
    var captureResult = Data([1, 2, 3])
    var captureError: Error?

    func listWindows() throws -> [CapturableWindow] {
        windows
    }

    func captureWindow(id: CGWindowID) throws -> Data {
        capturedWindowID = id
        if let captureError {
            throw captureError
        }
        return captureResult
    }
}

final class WindowCaptureServiceTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.windowCaptureProvider = CoreGraphicsWindowCaptureProvider()
        super.tearDown()
    }

    func testBridgeListsCapturableWindowsFromProvider() throws {
        let provider = FakeWindowCaptureProvider()
        AtlasBridge.windowCaptureProvider = provider

        let windows = try AtlasBridge.listCapturableWindows()

        XCTAssertEqual(windows, provider.windows)
    }

    func testBridgeCapturesWindowFromProvider() throws {
        let provider = FakeWindowCaptureProvider()
        AtlasBridge.windowCaptureProvider = provider

        let data = try AtlasBridge.captureWindow(id: 42)

        XCTAssertEqual(provider.capturedWindowID, 42)
        XCTAssertEqual(data, Data([1, 2, 3]))
    }

    func testCaptureErrorMessageIsLocalized() {
        let error = WindowCaptureError.captureFailed("denied")

        XCTAssertEqual(error.localizedDescription, "denied")
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/WindowCaptureServiceTests
```

Expected: FAIL because `WindowCaptureProviding`, `CapturableWindow`, and bridge methods do not exist.

- [x] **Step 3: Add window capture service**

Create `platforms/macos/Atlas/WindowCaptureService.swift`:

```swift
import AppKit
import CoreGraphics
import Foundation

struct CapturableWindow: Identifiable, Equatable {
    let id: CGWindowID
    let title: String
    let ownerName: String
    let bounds: CGRect
}

enum WindowCaptureError: LocalizedError, Equatable {
    case listFailed(String)
    case captureFailed(String)
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .listFailed(let message), .captureFailed(let message):
            return message
        case .imageEncodingFailed:
            return "Captured window image could not be encoded"
        }
    }
}

protocol WindowCaptureProviding {
    func listWindows() throws -> [CapturableWindow]
    func captureWindow(id: CGWindowID) throws -> Data
}

struct CoreGraphicsWindowCaptureProvider: WindowCaptureProviding {
    func listWindows() throws -> [CapturableWindow] {
        guard
            let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            throw WindowCaptureError.listFailed("Window list could not be read")
        }

        return rawWindows.compactMap { info in
            guard
                let number = info[kCGWindowNumber as String] as? UInt32,
                let ownerName = info[kCGWindowOwnerName as String] as? String,
                let boundsValue = info[kCGWindowBounds as String],
                let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary)
            else {
                return nil
            }

            let title = (info[kCGWindowName as String] as? String) ?? ownerName
            guard bounds.width >= 32, bounds.height >= 32 else { return nil }

            return CapturableWindow(
                id: CGWindowID(number),
                title: title.isEmpty ? ownerName : title,
                ownerName: ownerName,
                bounds: bounds
            )
        }
    }

    func captureWindow(id: CGWindowID) throws -> Data {
        guard
            let image = CGWindowListCreateImage(
                .null,
                [.optionIncludingWindow],
                id,
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            throw WindowCaptureError.captureFailed("Selected window could not be captured")
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw WindowCaptureError.imageEncodingFailed
        }
        return data
    }
}
```

- [x] **Step 4: Remove force-cast from bounds parsing**

Replace this block in `WindowCaptureService.swift`:

```swift
let boundsValue = info[kCGWindowBounds as String],
let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary)
```

with:

```swift
let boundsDictionary = info[kCGWindowBounds as String] as? CFDictionary,
let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
```

This keeps the service from crashing on malformed system window data.

- [x] **Step 5: Add bridge methods**

In `platforms/macos/Atlas/AtlasBridge.swift`, add this static property next to `captureService`:

```swift
static var windowCaptureProvider: WindowCaptureProviding = CoreGraphicsWindowCaptureProvider()
```

Add these methods below `captureFullScreen()`:

```swift
static func listCapturableWindows() throws -> [CapturableWindow] {
    try windowCaptureProvider.listWindows()
}

static func captureWindow(id: CGWindowID) throws -> Data {
    try windowCaptureProvider.captureWindow(id: id)
}
```

- [x] **Step 6: Add files to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so:

- `WindowCaptureService.swift` is in `Atlas` target Sources.
- `WindowCaptureServiceTests.swift` is in `AtlasTests` target Sources.

- [x] **Step 7: Run window service tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/WindowCaptureServiceTests
```

Expected: PASS, 3 tests.

- [x] **Step 8: Commit**

```bash
git add platforms/macos/Atlas/WindowCaptureService.swift \
  platforms/macos/Atlas/AtlasBridge.swift \
  platforms/macos/AtlasTests/WindowCaptureServiceTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add window capture service"
```

---

### Task 4: Window Selection UI

**Files:**
- Create: `platforms/macos/Atlas/WindowSelectionWindow.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Add window selection window**

Create `platforms/macos/Atlas/WindowSelectionWindow.swift`:

```swift
import AppKit
import SwiftUI

final class WindowSelectionWindow {
    private static var window: NSWindow?
    private static var delegate: WindowDelegate?

    static func show(
        windows: [CapturableWindow],
        onCancel: @escaping () -> Void = {},
        onSelect: @escaping (CapturableWindow) -> Void
    ) {
        if Thread.isMainThread {
            showOnMain(windows: windows, onCancel: onCancel, onSelect: onSelect)
        } else {
            DispatchQueue.main.async {
                showOnMain(windows: windows, onCancel: onCancel, onSelect: onSelect)
            }
        }
    }

    private static func showOnMain(
        windows: [CapturableWindow],
        onCancel: @escaping () -> Void,
        onSelect: @escaping (CapturableWindow) -> Void
    ) {
        close()

        let view = WindowSelectionView(
            windows: windows,
            onCancel: {
                close()
                onCancel()
            },
            onSelect: { selected in
                close()
                onSelect(selected)
            }
        )

        let controller = NSHostingController(rootView: view)
        let selectionWindow = SelectionPanel(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let windowDelegate = WindowDelegate {
            window = nil
            delegate = nil
        }

        selectionWindow.title = "Capture Window"
        selectionWindow.contentViewController = controller
        selectionWindow.center()
        selectionWindow.level = .floating
        selectionWindow.delegate = windowDelegate
        selectionWindow.isReleasedWhenClosed = false
        selectionWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = selectionWindow
        delegate = windowDelegate
    }

    private static func close() {
        window?.close()
        window = nil
        delegate = nil
    }

    private final class SelectionPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        private let onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func windowWillClose(_: Notification) {
            onClose()
        }
    }
}

private struct WindowSelectionView: View {
    let windows: [CapturableWindow]
    let onCancel: () -> Void
    let onSelect: (CapturableWindow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Window").font(.headline)

            List(windows) { window in
                Button {
                    onSelect(window)
                } label: {
                    HStack {
                        Image(systemName: "macwindow")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(window.title).lineLimit(1)
                            Text("\(window.ownerName) - \(Int(window.bounds.width))x\(Int(window.bounds.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }
}
```

- [x] **Step 2: Add file to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `WindowSelectionWindow.swift` is in the `Atlas` target Sources build phase.

- [x] **Step 3: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [x] **Step 4: Build app**

Run:

```bash
xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [x] **Step 5: Commit**

```bash
git add platforms/macos/Atlas/WindowSelectionWindow.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add window selection picker"
```

---

### Task 5: Wire Window Capture Into ContentView

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Modify: `platforms/macos/AtlasTests/AtlasBridgeCaptureTests.swift`

- [x] **Step 1: Update `showWindowSelection()`**

Replace the placeholder `showWindowSelection()` in `platforms/macos/Atlas/ContentView.swift` with:

```swift
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
```

Add this method below `showWindowSelection()`:

```swift
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
```

- [x] **Step 2: Extend bridge capture tests**

Append these tests to `platforms/macos/AtlasTests/AtlasBridgeCaptureTests.swift`:

```swift
private final class BridgeWindowProvider: WindowCaptureProviding {
    var windows = [
        CapturableWindow(id: 7, title: "Window", ownerName: "Atlas", bounds: CGRect(x: 0, y: 0, width: 100, height: 80))
    ]
    var capturedID: CGWindowID?

    func listWindows() throws -> [CapturableWindow] {
        windows
    }

    func captureWindow(id: CGWindowID) throws -> Data {
        capturedID = id
        return Data([4, 5, 6])
    }
}
```

Update `tearDown()` so it resets both providers:

```swift
override func tearDown() {
    AtlasBridge.captureService = .live
    AtlasBridge.windowCaptureProvider = CoreGraphicsWindowCaptureProvider()
    super.tearDown()
}
```

Add:

```swift
func testBridgeListsWindowsFromWindowProvider() throws {
    let provider = BridgeWindowProvider()
    AtlasBridge.windowCaptureProvider = provider

    let windows = try AtlasBridge.listCapturableWindows()

    XCTAssertEqual(windows, provider.windows)
}

func testBridgeCapturesWindowFromWindowProvider() throws {
    let provider = BridgeWindowProvider()
    AtlasBridge.windowCaptureProvider = provider

    let data = try AtlasBridge.captureWindow(id: 7)

    XCTAssertEqual(provider.capturedID, 7)
    XCTAssertEqual(data, Data([4, 5, 6]))
}
```

- [x] **Step 3: Run bridge tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/AtlasBridgeCaptureTests
```

Expected: PASS.

- [x] **Step 4: Run focused screenshot tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' \
  -only-testing:AtlasTests/AtlasBridgeCaptureTests \
  -only-testing:AtlasTests/WindowCaptureServiceTests \
  -only-testing:AtlasTests/ScreenshotCaptureModeTests \
  -only-testing:AtlasTests/ScreenCaptureCoordinateMapperTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add platforms/macos/Atlas/ContentView.swift platforms/macos/AtlasTests/AtlasBridgeCaptureTests.swift
git commit -m "feat(macos): wire selected window capture"
```

---

### Task 6: Update Verification Notes and Run Full Checks

**Files:**
- Modify: `docs/superpowers/plans/2026-05-10-uniffi-real-capture.md`
- Modify: `docs/superpowers/plans/2026-05-11-screenshot-capture-modes-v2.md`

- [x] **Step 1: Run Rust tests**

Run:

```bash
cargo test -p atlas-core -p atlas-ffi
```

Expected: PASS.

- [x] **Step 2: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [x] **Step 3: Run Xcode build**

Run:

```bash
xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [x] **Step 4: Run full Xcode tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected: TEST SUCCEEDED.

- [x] **Step 5: Append verification notes to this plan**

Append this section to `docs/superpowers/plans/2026-05-11-screenshot-capture-modes-v2.md`:

```markdown
## Execution Verification Notes

- Rust:
  - `cargo test -p atlas-core -p atlas-ffi`
  - Result: PASS
- Swift parse:
  - `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - Result: PASS
- Xcode:
  - `xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build`
  - Result: PASS
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: PASS
- Manual:
  - Desktop capture: Not performed in this automated run.
  - Window capture: Not performed in this automated run.
  - Area capture: Not performed in this automated run.
- Remaining limitations:
  - Desktop capture still uses the existing Rust full-screen API, which currently captures the first screen.
  - Window capture is macOS-only through CoreGraphics.
```

- [x] **Step 6: Add follow-up note to the UniFFI plan**

Append this section to `docs/superpowers/plans/2026-05-10-uniffi-real-capture.md`:

```markdown
## Follow-up: Screenshot Capture Modes v2

The UI now distinguishes desktop, window, and area capture. Desktop capture still uses the existing UniFFI full-screen API and keeps the primary-display limitation until a later multi-display capture plan replaces `CaptureEngine::capture_full_screen()`.
```

- [x] **Step 7: Commit**

```bash
git add docs/superpowers/plans/2026-05-10-uniffi-real-capture.md \
  docs/superpowers/plans/2026-05-11-screenshot-capture-modes-v2.md
git commit -m "docs: record screenshot capture mode verification"
```

---

### Task 7: Manual App Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-11-screenshot-capture-modes-v2.md`

- [x] **Step 1: Build and launch the app**

Run:

```bash
xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug -derivedDataPath /tmp/AtlasDerived build
open -n /tmp/AtlasDerived/Build/Products/Debug/Atlas.app
```

Expected: Atlas starts as a menu bar app.

- [x] **Step 2: Verify desktop capture manually**

In the app:

1. Open Atlas from the menu bar.
2. Click `Desktop`.
3. If macOS requests Screen Recording permission, grant it and relaunch Atlas.
4. Click `Desktop` again.

Expected: The editor opens with a captured image. If the machine has multiple displays, note whether only the primary display is captured.

- [x] **Step 3: Verify area capture manually**

In the app:

1. Click `Area`.
2. Drag a visible region.
3. Release the pointer.

Expected: The editor opens with the selected region and no obvious Retina double-scaling or offset.

- [x] **Step 4: Verify window capture manually**

In the app:

1. Click `Window`.
2. Pick a visible window from the picker.
3. Confirm the editor opens.

Expected: The editor opens with the selected window contents.

- [x] **Step 5: Verify output commands manually**

For one captured image:

1. Click Copy and paste into Preview or another image-capable app.
2. Click Save and open the saved file.
3. Click Pin and verify a pinned window appears.

Expected: copy/save/pin all use the edited screenshot data.

- [x] **Step 6: Record manual results**

Append this section to `docs/superpowers/plans/2026-05-11-screenshot-capture-modes-v2.md`:

```markdown
## Manual Verification Notes

- Desktop capture: [record observed result]
- Area capture: [record observed result]
- Window capture: [record observed result]
- Copy: [record observed result]
- Save: [record observed result]
- Pin: [record observed result]
- Permission behavior: [record Screen Recording prompt/relaunch behavior]
```

Replace each bracketed entry with the actual observed result before committing. Do not commit bracketed placeholder text.

- [x] **Step 7: Commit**

```bash
git add docs/superpowers/plans/2026-05-11-screenshot-capture-modes-v2.md
git commit -m "docs: record manual screenshot mode verification"
```

---

## Self-Review

1. **Spec coverage:** The plan implements all three requested screenshot modes: desktop, window, and area. Desktop and area reuse existing capture paths; window adds a macOS-specific provider and picker. It also preserves deterministic tests and records manual verification separately.
2. **Placeholder scan:** The only bracketed text appears in Task 7 as explicit manual result fields, and the task explicitly says not to commit those placeholders. Implementation tasks include concrete paths, code, commands, and expected outcomes.
3. **Type consistency:** `ScreenshotCaptureMode`, `CapturableWindow`, `WindowCaptureProviding`, `WindowCaptureError`, `CoreGraphicsWindowCaptureProvider`, `WindowSelectionWindow`, `AtlasBridge.listCapturableWindows()`, and `AtlasBridge.captureWindow(id:)` are defined before use and use consistent signatures across tasks.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-11-screenshot-capture-modes-v2.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

## Execution Verification Notes

- Rust:
  - `cargo test -p atlas-core -p atlas-ffi`
  - Result: PASS on 2026-05-23. `atlas-core` ran 21 tests with 0 failures, `atlas-ffi` ran 4 tests with 0 failures, and `atlas-core` doc-tests ran 0 tests with 0 failures.
- Swift parse:
  - `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - Result: PASS on 2026-05-23.
- Xcode:
  - `xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build`
  - Result: PASS on 2026-05-23. Build succeeded; Xcode emitted the standard CoreSimulator and destination-selection warnings.
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: PASS on 2026-05-23. XCTest ran 405 tests with 0 failures. Xcode emitted the standard CoreSimulator, destination-selection, and XCTest deployment-target warnings.
- Focused screenshot tests:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/AtlasBridgeCaptureTests -only-testing:AtlasTests/WindowCaptureServiceTests -only-testing:AtlasTests/ScreenshotCaptureModeTests -only-testing:AtlasTests/ScreenCaptureCoordinateMapperTests`
  - Result: PASS on 2026-05-23. The focused slice ran 16 tests with 0 failures.
- Manual:
  - Desktop capture: Not performed in this automated run.
  - Window capture: Not performed in this automated run.
  - Area capture: Not performed in this automated run.
- Remaining limitations:
  - Desktop capture still uses the existing Rust full-screen API, which currently captures the first screen.
  - Window capture is macOS-only through CoreGraphics.

## Manual Verification Waiver

Manual Desktop, Window, Area, Copy, Save, and Pin verification was not performed. On 2026-05-11, the user explicitly changed acceptance criteria so manual verification is not required for this task set; passing automated/unit tests is sufficient.
