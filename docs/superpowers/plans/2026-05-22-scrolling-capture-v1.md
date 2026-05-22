# Scrolling Capture v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add gated scrolling window capture that captures repeated window frames, stitches them into one PNG, and persists the result in the screenshot library.

**Architecture:** Keep the feature in the macOS layer because it depends on Screen Recording, Accessibility, CoreGraphics events, AppKit image stitching, and the existing Swift screenshot library. Build the capture loop behind small injectable protocols so unit tests can use fake frames and fake scroll events without requiring live permissions or moving the real pointer. Gate the UI through the existing screenshot Feature Center subfeature settings and keep the Rust `screenshot` module as the master enablement switch.

**Tech Stack:** SwiftUI, AppKit, CoreGraphics, ImageIO, XCTest, existing Atlas macOS Xcode project.

---

## Scope

This plan implements Scrolling Capture v1:

- Select a visible window, capture it repeatedly, send scroll events to the window, and stop when the configured maximum frame count is reached.
- Stitch captured PNG frames vertically with overlap trimming.
- Save the stitched PNG through `ScreenshotLibraryStore`.
- Open the stitched capture in the existing screenshot editor and floating thumbnail flow.
- Show explicit permission failures for missing Screen Recording or Accessibility permissions.
- Gate the entry point through Feature Center screenshot subfeature settings.
- Test without requiring live Screen Recording or Accessibility permissions by injecting fake permission providers, fake frame capture, fake scroll dispatch, and deterministic images.

Out of scope for v1:

- Horizontal scrolling.
- OCR during capture.
- Automatic bottom-of-scroll detection.
- Manual stop controls while scrolling capture is running.
- Rust or UniFFI changes.
- GIF recording.
- Live UI automation against third-party apps.

## File Structure

- `platforms/macos/Atlas/ScreenshotFeatureSettings.swift`
  - Add `scrollingCapture` as a disabled/enabled screenshot subfeature and expose it through capture capabilities.
- `platforms/macos/Atlas/ScreenshotScrollingCapture.swift`
  - Owns requests, results, permission protocols, frame capture protocol, scroll event protocol, service orchestration, and production adapters.
- `platforms/macos/Atlas/ScreenshotImageStitcher.swift`
  - Owns deterministic vertical image stitching from PNG frames.
- `platforms/macos/Atlas/ScreenshotPanel.swift`
  - Adds the Scrolling button when capability is enabled.
- `platforms/macos/Atlas/ContentView.swift`
  - Starts scrolling capture from selected window, saves result to the library, opens it in existing screenshot output/editor surfaces, and shows permission/status errors.
- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new source and test files.
- `platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift`
  - Extends subfeature and capability assertions.
- `platforms/macos/AtlasTests/ScreenshotScrollingCaptureTests.swift`
  - Unit tests for loop behavior, permission behavior, and library persistence with fakes.
- `platforms/macos/AtlasTests/ScreenshotImageStitcherTests.swift`
  - Unit tests for image output dimensions and overlap trimming.

---

### Task 1: Feature Center Gating

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotFeatureSettings.swift`
- Modify: `platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Extend settings tests for scrolling capture**

Add these assertions to `platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift`:

```swift
func testDefaultSettingsEnableScrollingCapture() {
    let settings = ScreenshotFeatureSettings.defaultEnabled

    XCTAssertTrue(settings.isEnabled(.scrollingCapture))
    XCTAssertTrue(settings.captureCapabilities.scrolling)
}

func testScrollingCaptureCanBeDisabled() {
    var settings = ScreenshotFeatureSettings.defaultEnabled
    settings.setEnabled(false, for: .scrollingCapture)

    XCTAssertFalse(settings.isEnabled(.scrollingCapture))
    XCTAssertFalse(settings.captureCapabilities.scrolling)
}
```

Update the stable order expectation in `testFeatureMetadataIsStable()` to:

```swift
XCTAssertEqual(ScreenshotSubfeature.allCases.map(\.rawValue), [
    "desktop-capture",
    "window-capture",
    "area-capture",
    "scrolling-capture",
    "annotations",
    "pinning",
    "ocr",
    "translation",
])
```

- [ ] **Step 2: Run settings tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests
```

Expected: FAIL because `ScreenshotSubfeature.scrollingCapture` and `ScreenshotCaptureCapabilities.scrolling` do not exist.

- [ ] **Step 3: Add the scrolling subfeature**

In `platforms/macos/Atlas/ScreenshotFeatureSettings.swift`, update the affected declarations to exactly include the new case and capability:

```swift
enum ScreenshotSubfeature: String, CaseIterable, Identifiable {
    case desktopCapture = "desktop-capture"
    case windowCapture = "window-capture"
    case areaCapture = "area-capture"
    case scrollingCapture = "scrolling-capture"
    case annotations
    case pinning
    case ocr
    case translation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktopCapture: return "Desktop Capture"
        case .windowCapture: return "Window Capture"
        case .areaCapture: return "Area Capture"
        case .scrollingCapture: return "Scrolling Capture"
        case .annotations: return "Annotations"
        case .pinning: return "Pinning"
        case .ocr: return "OCR"
        case .translation: return "Translation"
        }
    }

    var detail: String {
        switch self {
        case .desktopCapture: return "Capture the full desktop."
        case .windowCapture: return "Capture a selected application window."
        case .areaCapture: return "Capture a selected screen region."
        case .scrollingCapture: return "Capture and stitch a scrollable window."
        case .annotations: return "Show rectangle, arrow, pen, text, and pixelate tools."
        case .pinning: return "Pin screenshots in a floating window."
        case .ocr: return "Recognize text from screenshots."
        case .translation: return "Translate recognized screenshot text."
        }
    }

    var systemImage: String {
        switch self {
        case .desktopCapture: return "display"
        case .windowCapture: return "macwindow"
        case .areaCapture: return "selection.pin.in.out"
        case .scrollingCapture: return "rectangle.stack.badge.plus"
        case .annotations: return "pencil.and.outline"
        case .pinning: return "pin"
        case .ocr: return "text.viewfinder"
        case .translation: return "globe"
        }
    }
}

struct ScreenshotCaptureCapabilities: Equatable {
    var desktop: Bool
    var window: Bool
    var area: Bool
    var scrolling: Bool

    static let allEnabled = ScreenshotCaptureCapabilities(
        desktop: true,
        window: true,
        area: true,
        scrolling: true
    )
}
```

Update `ScreenshotFeatureSettings.captureCapabilities`:

```swift
var captureCapabilities: ScreenshotCaptureCapabilities {
    ScreenshotCaptureCapabilities(
        desktop: isEnabled(.desktopCapture),
        window: isEnabled(.windowCapture),
        area: isEnabled(.areaCapture),
        scrolling: isEnabled(.scrollingCapture)
    )
}
```

- [ ] **Step 4: Run settings tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests -only-testing:AtlasTests/ScreenshotFeatureSettingsPanelTests
```

Expected: PASS.

- [ ] **Step 5: Commit feature gating model**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotFeatureSettings.swift platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: gate scrolling screenshot capture"
```

Expected: Commit succeeds with only the settings/test/project updates.

---

### Task 2: Image Stitcher

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotImageStitcher.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotImageStitcherTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write stitcher tests**

Create `platforms/macos/AtlasTests/ScreenshotImageStitcherTests.swift`:

```swift
import AppKit
import XCTest
@testable import Atlas

final class ScreenshotImageStitcherTests: XCTestCase {
    func testStitchesFramesVerticallyWithoutOverlap() throws {
        let red = try png(width: 8, height: 5, color: .red)
        let blue = try png(width: 8, height: 7, color: .blue)

        let output = try VerticalScreenshotImageStitcher().stitch(
            frames: [red, blue],
            overlapPixels: 0
        )

        XCTAssertEqual(try dimensions(of: output), CGSize(width: 8, height: 12))
    }

    func testStitchesFramesWithFixedOverlapTrim() throws {
        let first = try png(width: 10, height: 8, color: .red)
        let second = try png(width: 10, height: 8, color: .blue)
        let third = try png(width: 10, height: 8, color: .green)

        let output = try VerticalScreenshotImageStitcher().stitch(
            frames: [first, second, third],
            overlapPixels: 3
        )

        XCTAssertEqual(try dimensions(of: output), CGSize(width: 10, height: 18))
    }

    func testRejectsEmptyFrameList() {
        XCTAssertThrowsError(
            try VerticalScreenshotImageStitcher().stitch(frames: [], overlapPixels: 0)
        ) { error in
            XCTAssertEqual(error as? ScreenshotImageStitchingError, .emptyFrames)
        }
    }

    private func png(width: Int, height: Int, color: NSColor) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw XCTSkip("Could not create test PNG")
        }
        return png
    }

    private func dimensions(of pngData: Data) throws -> CGSize {
        let image = try XCTUnwrap(NSImage(data: pngData))
        return image.size
    }
}
```

- [ ] **Step 2: Run stitcher tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotImageStitcherTests
```

Expected: FAIL because `VerticalScreenshotImageStitcher` does not exist or the test file is not in the project.

- [ ] **Step 3: Add the stitcher implementation**

Create `platforms/macos/Atlas/ScreenshotImageStitcher.swift`:

```swift
import AppKit

enum ScreenshotImageStitchingError: LocalizedError, Equatable {
    case emptyFrames
    case invalidFrame
    case outputEncodingFailed

    var errorDescription: String? {
        switch self {
        case .emptyFrames: return "Scrolling capture did not produce any frames"
        case .invalidFrame: return "Scrolling capture produced an invalid image frame"
        case .outputEncodingFailed: return "Scrolling capture could not encode the stitched PNG"
        }
    }
}

protocol ScreenshotImageStitching {
    func stitch(frames: [Data], overlapPixels: Int) throws -> Data
}

struct VerticalScreenshotImageStitcher: ScreenshotImageStitching {
    func stitch(frames: [Data], overlapPixels: Int) throws -> Data {
        guard !frames.isEmpty else { throw ScreenshotImageStitchingError.emptyFrames }

        let images = try frames.map { data -> NSImage in
            guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
                throw ScreenshotImageStitchingError.invalidFrame
            }
            return image
        }

        let width = images.map(\.size.width).max() ?? 0
        let trimmedOverlap = max(0, overlapPixels)
        let height = images.enumerated().reduce(CGFloat(0)) { total, entry in
            total + entry.element.size.height - CGFloat(entry.offset == 0 ? 0 : min(trimmedOverlap, Int(entry.element.size.height)))
        }

        let output = NSImage(size: NSSize(width: width, height: height))
        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: output.size).fill()

        var y = height
        for (index, image) in images.enumerated() {
            let cropTop = CGFloat(index == 0 ? 0 : min(trimmedOverlap, Int(image.size.height)))
            let drawHeight = image.size.height - cropTop
            y -= drawHeight
            image.draw(
                in: NSRect(x: 0, y: y, width: image.size.width, height: drawHeight),
                from: NSRect(x: 0, y: 0, width: image.size.width, height: drawHeight),
                operation: .copy,
                fraction: 1
            )
        }
        output.unlockFocus()

        guard
            let tiff = output.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw ScreenshotImageStitchingError.outputEncodingFailed
        }

        return png
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Add:

- `ScreenshotImageStitcher.swift` to the `Atlas` target Sources.
- `ScreenshotImageStitcherTests.swift` to the `AtlasTests` target Sources.

Do not reorder unrelated project entries.

- [ ] **Step 5: Run stitcher tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotImageStitcherTests
```

Expected: PASS with 3 tests.

- [ ] **Step 6: Commit stitcher**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotImageStitcher.swift platforms/macos/AtlasTests/ScreenshotImageStitcherTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: stitch scrolling screenshot frames"
```

Expected: Commit succeeds with only stitcher files and project membership.

---

### Task 3: Scrolling Capture Service

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotScrollingCapture.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotScrollingCaptureTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write service tests**

Create `platforms/macos/AtlasTests/ScreenshotScrollingCaptureTests.swift`:

```swift
import AppKit
import XCTest
@testable import Atlas

final class ScreenshotScrollingCaptureTests: XCTestCase {
    func testCapturesFramesScrollsBetweenFramesAndPersistsLibraryItem() throws {
        let frame = try png(width: 8, height: 4, color: .red)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollingCaptureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let libraryStore = ScreenshotLibraryStore(rootDirectory: storeRoot)
        let frameCapture = StubScrollingFrameCapture(frames: [frame, frame, frame])
        let scroller = StubScrollEventSender()

        let result = try ScreenshotScrollingCaptureService(
            permissions: StubScrollingPermissions(screenRecordingAllowed: true, accessibilityAllowed: true),
            frameCapture: frameCapture,
            scrollSender: scroller,
            stitcher: VerticalScreenshotImageStitcher(),
            libraryStore: libraryStore
        ).capture(
            request: ScrollingCaptureRequest(
                window: CapturableWindow(id: 42, title: "Document", ownerName: "Preview", bounds: .zero),
                maxFrames: 3,
                scrollDelta: -8,
                overlapPixels: 0
            )
        )

        XCTAssertEqual(frameCapture.windowIDs, [42, 42, 42])
        XCTAssertEqual(scroller.windowIDs, [42, 42])
        XCTAssertEqual(result.framesCaptured, 3)
        XCTAssertEqual(result.libraryItem.source, "Scrolling Window: Preview - Document")
        XCTAssertEqual(try libraryStore.loadItems(), [result.libraryItem])
        XCTAssertEqual(try libraryStore.pngData(for: result.libraryItem), result.pngData)
    }

    func testStopsAtMaximumFrames() throws {
        let frame = try png(width: 8, height: 4, color: .blue)
        let service = ScreenshotScrollingCaptureService(
            permissions: StubScrollingPermissions(screenRecordingAllowed: true, accessibilityAllowed: true),
            frameCapture: StubScrollingFrameCapture(frames: [frame, frame, frame, frame]),
            scrollSender: StubScrollEventSender(),
            stitcher: VerticalScreenshotImageStitcher(),
            libraryStore: ScreenshotLibraryStore(rootDirectory: temporaryRoot())
        )

        let result = try service.capture(
            request: ScrollingCaptureRequest(
                window: CapturableWindow(id: 7, title: "Feed", ownerName: "Safari", bounds: .zero),
                maxFrames: 2,
                scrollDelta: -5,
                overlapPixels: 0
            )
        )

        XCTAssertEqual(result.framesCaptured, 2)
    }

    func testReportsMissingScreenRecordingPermissionBeforeCapture() {
        let service = ScreenshotScrollingCaptureService(
            permissions: StubScrollingPermissions(screenRecordingAllowed: false, accessibilityAllowed: true),
            frameCapture: StubScrollingFrameCapture(frames: []),
            scrollSender: StubScrollEventSender(),
            stitcher: VerticalScreenshotImageStitcher(),
            libraryStore: ScreenshotLibraryStore(rootDirectory: temporaryRoot())
        )

        XCTAssertThrowsError(try service.capture(request: request())) { error in
            XCTAssertEqual(error as? ScrollingCaptureError, .screenRecordingPermissionMissing)
        }
    }

    func testReportsMissingAccessibilityPermissionBeforeCapture() {
        let service = ScreenshotScrollingCaptureService(
            permissions: StubScrollingPermissions(screenRecordingAllowed: true, accessibilityAllowed: false),
            frameCapture: StubScrollingFrameCapture(frames: []),
            scrollSender: StubScrollEventSender(),
            stitcher: VerticalScreenshotImageStitcher(),
            libraryStore: ScreenshotLibraryStore(rootDirectory: temporaryRoot())
        )

        XCTAssertThrowsError(try service.capture(request: request())) { error in
            XCTAssertEqual(error as? ScrollingCaptureError, .accessibilityPermissionMissing)
        }
    }

    private func request() -> ScrollingCaptureRequest {
        ScrollingCaptureRequest(
            window: CapturableWindow(id: 1, title: "Doc", ownerName: "App", bounds: .zero),
            maxFrames: 3,
            scrollDelta: -6,
            overlapPixels: 0
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollingCaptureTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func png(width: Int, height: Int, color: NSColor) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

private final class StubScrollingFrameCapture: ScrollingWindowFrameCapturing {
    private var frames: [Data]
    private(set) var windowIDs: [CGWindowID] = []

    init(frames: [Data]) {
        self.frames = frames
    }

    func captureWindowFrame(id: CGWindowID) throws -> Data {
        windowIDs.append(id)
        return frames.removeFirst()
    }
}

private final class StubScrollEventSender: WindowScrollEventSending {
    private(set) var windowIDs: [CGWindowID] = []

    func scrollWindow(id: CGWindowID, deltaY: Int32) throws {
        windowIDs.append(id)
    }
}

private struct StubScrollingPermissions: ScrollingCapturePermissionProviding {
    let screenRecordingAllowed: Bool
    let accessibilityAllowed: Bool
}
```

- [ ] **Step 2: Run service tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotScrollingCaptureTests
```

Expected: FAIL because scrolling capture service types do not exist or the test file is not in the project.

- [ ] **Step 3: Add the scrolling capture service**

Create `platforms/macos/Atlas/ScreenshotScrollingCapture.swift`:

```swift
import AppKit
import CoreGraphics

struct ScrollingCaptureRequest: Equatable {
    let window: CapturableWindow
    let maxFrames: Int
    let scrollDelta: Int32
    let overlapPixels: Int
}

struct ScrollingCaptureResult: Equatable {
    let pngData: Data
    let framesCaptured: Int
    let libraryItem: ScreenshotLibraryItem
}

enum ScrollingCaptureError: LocalizedError, Equatable {
    case screenRecordingPermissionMissing
    case accessibilityPermissionMissing
    case noFramesCaptured

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionMissing:
            return "Screen Recording permission is required for scrolling capture"
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required to scroll the selected window"
        case .noFramesCaptured:
            return "Scrolling capture did not capture any frames"
        }
    }
}

protocol ScrollingCapturePermissionProviding {
    var screenRecordingAllowed: Bool { get }
    var accessibilityAllowed: Bool { get }
}

struct LiveScrollingCapturePermissions: ScrollingCapturePermissionProviding {
    var screenRecordingAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var accessibilityAllowed: Bool {
        AXIsProcessTrusted()
    }
}

protocol ScrollingWindowFrameCapturing {
    func captureWindowFrame(id: CGWindowID) throws -> Data
}

struct AtlasScrollingWindowFrameCapture: ScrollingWindowFrameCapturing {
    func captureWindowFrame(id: CGWindowID) throws -> Data {
        try AtlasBridge.captureWindow(id: id)
    }
}

protocol WindowScrollEventSending {
    func scrollWindow(id: CGWindowID, deltaY: Int32) throws
}

struct CGWindowScrollEventSender: WindowScrollEventSending {
    func scrollWindow(id: CGWindowID, deltaY: Int32) throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.12)
    }
}

struct ScreenshotScrollingCaptureService {
    let permissions: ScrollingCapturePermissionProviding
    let frameCapture: ScrollingWindowFrameCapturing
    let scrollSender: WindowScrollEventSending
    let stitcher: ScreenshotImageStitching
    let libraryStore: ScreenshotLibraryStore

    init(
        permissions: ScrollingCapturePermissionProviding = LiveScrollingCapturePermissions(),
        frameCapture: ScrollingWindowFrameCapturing = AtlasScrollingWindowFrameCapture(),
        scrollSender: WindowScrollEventSending = CGWindowScrollEventSender(),
        stitcher: ScreenshotImageStitching = VerticalScreenshotImageStitcher(),
        libraryStore: ScreenshotLibraryStore = ScreenshotLibraryStore()
    ) {
        self.permissions = permissions
        self.frameCapture = frameCapture
        self.scrollSender = scrollSender
        self.stitcher = stitcher
        self.libraryStore = libraryStore
    }

    func capture(request: ScrollingCaptureRequest) throws -> ScrollingCaptureResult {
        guard permissions.screenRecordingAllowed else {
            throw ScrollingCaptureError.screenRecordingPermissionMissing
        }
        guard permissions.accessibilityAllowed else {
            throw ScrollingCaptureError.accessibilityPermissionMissing
        }

        let maxFrames = max(1, request.maxFrames)
        var frames: [Data] = []

        for index in 0..<maxFrames {
            frames.append(try frameCapture.captureWindowFrame(id: request.window.id))
            if index == maxFrames - 1 { break }
            try scrollSender.scrollWindow(id: request.window.id, deltaY: request.scrollDelta)
        }

        guard !frames.isEmpty else {
            throw ScrollingCaptureError.noFramesCaptured
        }

        let output = try stitcher.stitch(frames: frames, overlapPixels: request.overlapPixels)
        let dimensions = NSImage(data: output)?.size ?? request.window.bounds.size
        let item = try libraryStore.addScreenshot(
            pngData: output,
            pixelWidth: Int(dimensions.width.rounded()),
            pixelHeight: Int(dimensions.height.rounded()),
            source: "Scrolling Window: \(request.window.ownerName) - \(request.window.title)"
        )

        return ScrollingCaptureResult(
            pngData: output,
            framesCaptured: frames.count,
            libraryItem: item
        )
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Add:

- `ScreenshotScrollingCapture.swift` to the `Atlas` target Sources.
- `ScreenshotScrollingCaptureTests.swift` to the `AtlasTests` target Sources.

- [ ] **Step 5: Run service tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotScrollingCaptureTests
```

Expected: PASS with 4 tests.

- [ ] **Step 6: Commit service**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotScrollingCapture.swift platforms/macos/AtlasTests/ScreenshotScrollingCaptureTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: add scrolling screenshot capture service"
```

Expected: Commit succeeds.

---

### Task 4: UI Wiring and Output Flow

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotPanel.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Add the Scrolling button to the screenshot panel**

Update `ScreenshotPanel` with the new callback and button:

```swift
struct ScreenshotPanel: View {
    let capabilities: ScreenshotCaptureCapabilities
    let onCaptureDesktop: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureArea: () -> Void
    let onCaptureScrolling: () -> Void

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
                if capabilities.scrolling {
                    Button(action: onCaptureScrolling) {
                        Label("Scrolling", systemImage: "rectangle.stack.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Wire `ContentView` to select a window and start scrolling capture**

In `platforms/macos/Atlas/ContentView.swift`, add this property beside the existing screenshot services:

```swift
private let scrollingCaptureService = ScreenshotScrollingCaptureService()
```

Update every `ScreenshotPanel(...)` call to pass:

```swift
onCaptureScrolling: startScrollingWindowCapture
```

Add these helpers near the existing window capture helpers:

```swift
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
        let screenshot = CapturedScreenshot(
            pngData: result.pngData,
            rect: CGRect(origin: .zero, size: CGSize(width: result.libraryItem.pixelWidth, height: result.libraryItem.pixelHeight))
        )
        setCapturedScreenshot(screenshot, source: result.libraryItem.source, libraryItemID: result.libraryItem.id)
        loadScreenshotLibrary()
        showStatus("Captured scrolling window")
    } catch {
        showStatus(error.localizedDescription, kind: .error)
    }
}
```

The existing `setCapturedScreenshot(_:source:)` helper records a new library item. Because `ScreenshotScrollingCaptureService` already persists the stitched image, replace that helper with this overload before using `captureScrollingWindow(_:)`:

```swift
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
```

Keep the existing desktop, area, and window capture call sites unchanged; the default `nil` value preserves their current library recording behavior.

- [ ] **Step 3: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [ ] **Step 4: Run focused scrolling tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests -only-testing:AtlasTests/ScreenshotImageStitcherTests -only-testing:AtlasTests/ScreenshotScrollingCaptureTests
```

Expected: PASS.

- [ ] **Step 5: Commit UI wiring**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotPanel.swift platforms/macos/Atlas/ContentView.swift
git commit -m "feat: wire scrolling capture into screenshot UI"
```

Expected: Commit succeeds.

---

### Task 5: Final Verification

**Files:**
- Read: all files modified by this plan.

- [ ] **Step 1: Run screenshot tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotCaptureModeTests -only-testing:AtlasTests/AtlasCaptureServiceTests -only-testing:AtlasTests/ScreenshotLibraryTests -only-testing:AtlasTests/ScreenshotFeatureSettingsTests -only-testing:AtlasTests/ScreenshotFeatureSettingsPanelTests -only-testing:AtlasTests/ScreenshotImageStitcherTests -only-testing:AtlasTests/ScreenshotScrollingCaptureTests
```

Expected: PASS.

- [ ] **Step 2: Verify no Rust changes are needed**

Run:

```bash
git diff -- crates/atlas-core crates/atlas-ffi
```

Expected: no output.

- [ ] **Step 3: Commit final plan note if this plan file is updated**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-scrolling-capture-v1.md
git commit -m "docs: record scrolling capture verification"
```

Expected: Commit succeeds only if verification notes were added to this plan.
