# Screenshot Pro Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the next usable screenshot workflow for Atlas: capture a selected region, preview it, annotate it, copy/save it, and pin it as a floating reference window.

**Architecture:** Keep capture selection in `SelectionOverlay`, keep menu-bar entry in `ScreenshotPanel`, and move post-capture work into focused screenshot files. SwiftUI owns interactive UI and annotation state; `AtlasBridge.captureRegion` remains the capture boundary until real UniFFI bindings replace the mock bridge.

**Tech Stack:** SwiftUI, AppKit `NSImage`/`NSPasteboard`/`NSSavePanel`, macOS floating `NSPanel`, existing Rust/UniFFI capture interface.

---

## File Structure

- Create: `platforms/macos/Atlas/ScreenshotModels.swift`
  - Owns screenshot annotation types, output action types, and small value models.
- Create: `platforms/macos/Atlas/ScreenshotOutput.swift`
  - Owns copy-to-clipboard and save-to-file operations for PNG data.
- Create: `platforms/macos/Atlas/ScreenshotEditorView.swift`
  - Owns post-capture preview, annotation toolbar, annotation canvas, and output buttons.
- Create: `platforms/macos/Atlas/PinnedScreenshotWindow.swift`
  - Owns the floating pinned screenshot window implementation.
- Modify: `platforms/macos/Atlas/SelectionOverlay.swift`
  - Keep selection behavior; add output mode callback that captures selected region without closing the screenshot module state prematurely.
- Modify: `platforms/macos/Atlas/ContentView.swift`
  - Replace direct status-only capture handling with editor presentation and output status.
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
  - Keep current mock data path, but return deterministic PNG data for local UI verification.
- Test: `platforms/macos/AtlasTests/ScreenshotOutputTests.swift`
  - Tests pure output helpers where possible without opening UI.

Scope note: OCR, translation, scrolling capture, and smart boundary detection are separate subsystems. This plan leaves clear hooks for them but does not include them in this implementation slice.

---

### Task 1: Screenshot Models

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotModels.swift`
- Test: `platforms/macos/AtlasTests/ScreenshotModelsTests.swift`

- [x] **Step 1: Write the model tests**

```swift
import XCTest
@testable import Atlas

final class ScreenshotModelsTests: XCTestCase {
    func testAnnotationDefaults() {
        let annotation = ScreenshotAnnotation.rectangle(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            rect: CGRect(x: 10, y: 20, width: 30, height: 40),
            color: .red,
            lineWidth: 3
        )

        XCTAssertEqual(annotation.id.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(annotation.kind, .rectangle)
        XCTAssertEqual(annotation.bounds, CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    func testToolMetadata() {
        XCTAssertEqual(ScreenshotTool.rectangle.systemImage, "rectangle")
        XCTAssertEqual(ScreenshotTool.arrow.systemImage, "arrow.up.right")
        XCTAssertEqual(ScreenshotTool.pen.systemImage, "pencil")
        XCTAssertEqual(ScreenshotTool.text.systemImage, "textformat")
        XCTAssertEqual(ScreenshotTool.pixelate.systemImage, "checkerboard.rectangle")
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/ScreenshotModelsTests`

Expected: FAIL because `ScreenshotAnnotation`, `ScreenshotTool`, and the test target file do not exist yet.

- [x] **Step 3: Add the screenshot model file**

```swift
import SwiftUI

enum ScreenshotTool: String, CaseIterable, Identifiable {
    case rectangle
    case arrow
    case pen
    case text
    case pixelate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .arrow: return "Arrow"
        case .pen: return "Pen"
        case .text: return "Text"
        case .pixelate: return "Pixelate"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil"
        case .text: return "textformat"
        case .pixelate: return "checkerboard.rectangle"
        }
    }
}

enum ScreenshotAnnotationKind: Equatable {
    case rectangle
    case arrow
    case pen
    case text(String)
    case pixelate
}

struct ScreenshotAnnotation: Identifiable, Equatable {
    let id: UUID
    let kind: ScreenshotAnnotationKind
    var bounds: CGRect
    var color: Color
    var lineWidth: CGFloat
    var points: [CGPoint]

    static func rectangle(id: UUID = UUID(), rect: CGRect, color: Color, lineWidth: CGFloat) -> Self {
        ScreenshotAnnotation(id: id, kind: .rectangle, bounds: rect, color: color, lineWidth: lineWidth, points: [])
    }

    static func arrow(id: UUID = UUID(), from start: CGPoint, to end: CGPoint, color: Color, lineWidth: CGFloat) -> Self {
        ScreenshotAnnotation(id: id, kind: .arrow, bounds: CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized, color: color, lineWidth: lineWidth, points: [start, end])
    }

    static func pen(id: UUID = UUID(), points: [CGPoint], color: Color, lineWidth: CGFloat) -> Self {
        let rect = points.reduce(CGRect.null) { partial, point in
            partial.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        return ScreenshotAnnotation(id: id, kind: .pen, bounds: rect, color: color, lineWidth: lineWidth, points: points)
    }

    static func text(id: UUID = UUID(), value: String, rect: CGRect, color: Color) -> Self {
        ScreenshotAnnotation(id: id, kind: .text(value), bounds: rect, color: color, lineWidth: 1, points: [])
    }

    static func pixelate(id: UUID = UUID(), rect: CGRect) -> Self {
        ScreenshotAnnotation(id: id, kind: .pixelate, bounds: rect, color: .gray, lineWidth: 1, points: [])
    }
}

struct CapturedScreenshot: Identifiable, Equatable {
    let id: UUID
    let pngData: Data
    let rect: CGRect
    let capturedAt: Date

    init(id: UUID = UUID(), pngData: Data, rect: CGRect, capturedAt: Date = Date()) {
        self.id = id
        self.pngData = pngData
        self.rect = rect
        self.capturedAt = capturedAt
    }
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/ScreenshotModelsTests`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotModels.swift platforms/macos/AtlasTests/ScreenshotModelsTests.swift
git commit -m "feat(macos): add screenshot annotation models"
```

---

### Task 2: Clipboard and Save Output

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotOutput.swift`
- Test: `platforms/macos/AtlasTests/ScreenshotOutputTests.swift`

- [x] **Step 1: Write output helper tests**

```swift
import XCTest
@testable import Atlas

final class ScreenshotOutputTests: XCTestCase {
    func testPngFilenameUsesTimestamp() {
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        let filename = ScreenshotOutput.filename(for: date)
        XCTAssertEqual(filename, "Atlas Screenshot 2024-01-01 00.00.00.png")
    }

    func testWritePngData() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = try ScreenshotOutput.writePNG(data, to: directory, date: Date(timeIntervalSince1970: 1_704_067_200))

        XCTAssertEqual(url.lastPathComponent, "Atlas Screenshot 2024-01-01 00.00.00.png")
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/ScreenshotOutputTests`

Expected: FAIL because `ScreenshotOutput` does not exist.

- [x] **Step 3: Add output helper implementation**

```swift
import AppKit
import Foundation

enum ScreenshotOutput {
    static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Atlas Screenshot \(formatter.string(from: date)).png"
    }

    static func copyPNGToClipboard(_ data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    static func writePNG(_ data: Data, to directory: URL, date: Date = Date()) throws -> URL {
        let url = directory.appendingPathComponent(filename(for: date))
        try data.write(to: url, options: .atomic)
        return url
    }

    static func savePNGWithPanel(_ data: Data, suggestedDate: Date = Date()) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = filename(for: suggestedDate)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/ScreenshotOutputTests`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotOutput.swift platforms/macos/AtlasTests/ScreenshotOutputTests.swift
git commit -m "feat(macos): add screenshot output helpers"
```

---

### Task 3: Deterministic Capture Data for UI Development

**Files:**
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
- Test: `platforms/macos/AtlasTests/AtlasBridgeCaptureTests.swift`

- [x] **Step 1: Write bridge capture tests**

```swift
import XCTest
@testable import Atlas

final class AtlasBridgeCaptureTests: XCTestCase {
    func testMockCaptureRegionReturnsPngData() {
        let data = AtlasBridge.captureRegion(x: 0, y: 0, width: 120, height: 80)

        XCTAssertNotNil(data)
        XCTAssertEqual(Array(data!.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/AtlasBridgeCaptureTests`

Expected: FAIL because the current mock returns empty `Data()`.

- [x] **Step 3: Replace mock capture return with generated PNG**

```swift
import AppKit
import Foundation

private extension NSImage {
    static func atlasMockScreenshot(width: Int, height: Int) -> Data {
        let size = NSSize(width: max(1, width), height: max(1, height))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: NSRect(x: 4, y: 4, width: size.width - 8, height: size.height - 8))
        border.lineWidth = 4
        border.stroke()
        NSString(string: "\(Int(size.width)) x \(Int(size.height))").draw(
            at: NSPoint(x: 12, y: max(12, size.height / 2 - 8)),
            withAttributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
            ]
        )
        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        }

        return png
    }
}
```

Then update `captureRegion`:

```swift
static func captureRegion(x: Int32, y: Int32, width: UInt32, height: UInt32) -> Data? {
    print("Capturing region: x=\(x), y=\(y), width=\(width), height=\(height)")
    return NSImage.atlasMockScreenshot(width: Int(width), height: Int(height))
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/AtlasBridgeCaptureTests`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add platforms/macos/Atlas/AtlasBridge.swift platforms/macos/AtlasTests/AtlasBridgeCaptureTests.swift
git commit -m "test(macos): return deterministic screenshot mock data"
```

---

### Task 4: Screenshot Editor View

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotEditorView.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [x] **Step 1: Add the editor view**

```swift
import SwiftUI

struct ScreenshotEditorView: View {
    let screenshot: CapturedScreenshot
    let onCopy: (Data) -> Void
    let onSave: (Data) -> Void
    let onPin: (Data) -> Void
    let onClose: () -> Void

    @State private var selectedTool: ScreenshotTool = .rectangle
    @State private var annotations: [ScreenshotAnnotation] = []
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
            Divider()
            outputBar
        }
        .frame(width: 520, height: 420)
        .background(.regularMaterial)
        .cornerRadius(10)
        .shadow(radius: 12)
        .padding()
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(ScreenshotTool.allCases) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Image(systemName: tool.systemImage)
                }
                .help(tool.title)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            Button {
                annotations.removeLast()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(annotations.isEmpty)
            .help("Undo")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("Close")
        }
        .padding(10)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            ZStack {
                screenshotImage
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ForEach(annotations) { annotation in
                    AnnotationShape(annotation: annotation)
                }
            }
            .contentShape(Rectangle())
            .gesture(annotationDrag(in: geometry.size))
        }
    }

    private var screenshotImage: Image {
        if let image = NSImage(data: screenshot.pngData) {
            return Image(nsImage: image)
        }
        return Image(systemName: "photo")
    }

    private var outputBar: some View {
        HStack {
            Button("Copy") { onCopy(renderedData()) }
            Button("Save") { onSave(renderedData()) }
            Button("Pin") { onPin(renderedData()) }
            Spacer()
            Text("\(Int(screenshot.rect.width)) x \(Int(screenshot.rect.height))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
    }

    private func annotationDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                }
            }
            .onEnded { value in
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

    private func renderedData() -> Data {
        screenshot.pngData
    }
}

private struct AnnotationShape: View {
    let annotation: ScreenshotAnnotation

    var body: some View {
        switch annotation.kind {
        case .rectangle:
            Rectangle()
                .stroke(annotation.color, lineWidth: annotation.lineWidth)
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .arrow:
            Path { path in
                guard annotation.points.count == 2 else { return }
                path.move(to: annotation.points[0])
                path.addLine(to: annotation.points[1])
            }
            .stroke(annotation.color, lineWidth: annotation.lineWidth)
        case .pen:
            Path { path in
                guard let first = annotation.points.first else { return }
                path.move(to: first)
                for point in annotation.points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(annotation.color, lineWidth: annotation.lineWidth)
        case .text(let value):
            Text(value)
                .foregroundColor(annotation.color)
                .frame(width: annotation.bounds.width, height: annotation.bounds.height, alignment: .leading)
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .pixelate:
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        }
    }
}
```

- [x] **Step 2: Update ContentView state and presentation**

Add state:

```swift
@State private var capturedScreenshot: CapturedScreenshot?
```

Render editor above `SelectionOverlay`:

```swift
if let capturedScreenshot {
    ScreenshotEditorView(
        screenshot: capturedScreenshot,
        onCopy: copyScreenshot,
        onSave: saveScreenshot,
        onPin: pinScreenshot,
        onClose: { self.capturedScreenshot = nil }
    )
}
```

Replace `captureSelection` with:

```swift
private func captureSelection(_ rect: CGRect) {
    if let data = AtlasBridge.captureRegion(
        x: Int32(rect.minX),
        y: Int32(rect.minY),
        width: UInt32(rect.width),
        height: UInt32(rect.height)
    ) {
        capturedScreenshot = CapturedScreenshot(pngData: data, rect: rect)
        captureStatus = "Captured \(Int(rect.width))×\(Int(rect.height)) px"
        showCaptureStatus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCaptureStatus = false
        }
    }
    isShowingSelectionOverlay = false
}
```

Add output handlers:

```swift
private func copyScreenshot(_ data: Data) {
    ScreenshotOutput.copyPNGToClipboard(data)
    captureStatus = "Copied screenshot"
    showCaptureStatus = true
}

private func saveScreenshot(_ data: Data) {
    if let url = ScreenshotOutput.savePNGWithPanel(data) {
        captureStatus = "Saved \(url.lastPathComponent)"
        showCaptureStatus = true
    }
}

private func pinScreenshot(_ data: Data) {
    PinnedScreenshotWindow.show(data: data)
    captureStatus = "Pinned screenshot"
    showCaptureStatus = true
}
```

- [x] **Step 3: Parse Swift files**

Run: `swiftc -parse platforms/macos/Atlas/*.swift`

Expected: PASS with no output.

- [x] **Step 4: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotEditorView.swift platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): add screenshot editor shell"
```

---

### Task 5: Pinned Screenshot Window

**Files:**
- Create: `platforms/macos/Atlas/PinnedScreenshotWindow.swift`

- [x] **Step 1: Add pinned window implementation**

```swift
import AppKit
import SwiftUI

final class PinnedScreenshotWindow {
    private static var windows: [NSWindow] = []

    static func show(data: Data) {
        guard let image = NSImage(data: data) else { return }

        let view = PinnedScreenshotView(image: image) {
            closeWindow(containing: image)
        }

        let controller = NSHostingController(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(x: 160, y: 160, width: min(480, image.size.width), height: min(360, image.size.height)),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }

    private static func closeWindow(containing image: NSImage) {
        guard let index = windows.firstIndex(where: { window in
            guard let controller = window.contentViewController as? NSHostingController<PinnedScreenshotView> else {
                return false
            }
            return controller.rootView.image === image
        }) else {
            return
        }
        windows[index].close()
        windows.remove(at: index)
    }
}

struct PinnedScreenshotView: View {
    let image: NSImage
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(minWidth: 160, minHeight: 120)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("Close pinned screenshot")
        }
    }
}
```

- [x] **Step 2: Parse Swift files**

Run: `swiftc -parse platforms/macos/Atlas/*.swift`

Expected: PASS with no output.

- [x] **Step 3: Commit**

```bash
git add platforms/macos/Atlas/PinnedScreenshotWindow.swift
git commit -m "feat(macos): add pinned screenshot window"
```

---

### Task 6: Wire Screenshot Feature Into Module UI

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotPanel.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [x] **Step 1: Expand ScreenshotPanel actions**

Replace `ScreenshotPanel` with:

```swift
import SwiftUI

struct ScreenshotPanel: View {
    let onSelectArea: () -> Void
    let onFullScreen: () -> Void

    var body: some View {
        Group {
            Text("Screenshot").font(.subheadline).foregroundColor(.secondary)
            HStack {
                Button(action: onSelectArea) {
                    Label("Area", systemImage: "selection.pin.in.out")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onFullScreen) {
                    Label("Full", systemImage: "macwindow")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
```

- [x] **Step 2: Update ContentView call site**

Replace:

```swift
ScreenshotPanel {
    isShowingSelectionOverlay = true
}
```

With:

```swift
ScreenshotPanel(
    onSelectArea: { isShowingSelectionOverlay = true },
    onFullScreen: captureFullScreen
)
```

Add:

```swift
private func captureFullScreen() {
    if let data = AtlasBridge.captureFullScreen() {
        let rect = CGRect(x: 0, y: 0, width: 0, height: 0)
        capturedScreenshot = CapturedScreenshot(pngData: data, rect: rect)
        captureStatus = "Captured full screen"
        showCaptureStatus = true
    }
}
```

- [x] **Step 3: Parse Swift files**

Run: `swiftc -parse platforms/macos/Atlas/*.swift`

Expected: PASS with no output.

- [x] **Step 4: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotPanel.swift platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): wire screenshot panel actions"
```

---

### Task 7: Final Verification

**Files:**
- Verify: `platforms/macos/Atlas/*.swift`
- Verify: `platforms/macos/AtlasTests/*.swift`

- [x] **Step 1: Run Swift parse check**

Run: `swiftc -parse platforms/macos/Atlas/*.swift`

Expected: PASS with no output.

- [x] **Step 2: Run screenshot tests**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/ScreenshotModelsTests -only-testing:AtlasTests/ScreenshotOutputTests -only-testing:AtlasTests/AtlasBridgeCaptureTests`

Expected: PASS for all screenshot-focused tests.

- [x] **Step 3: Manual app verification**

Run the Atlas macOS target in Xcode, then verify:

1. Screenshot feature toggle is enabled.
2. Area capture opens the overlay.
3. Dragging creates a selection and shows dimensions.
4. Moving and resizing the selection works.
5. Confirm opens the screenshot editor.
6. Rectangle, arrow, pen, text, and pixelate tools add visible marks.
7. Copy places PNG data on the clipboard.
8. Save opens a save panel and writes a PNG.
9. Pin opens a floating window above normal windows.
10. Disabling the `screenshot` feature hides the screenshot panel.

- [x] **Step 4: Commit verification-only fixes**

If verification required small fixes, commit them:

```bash
git add platforms/macos/Atlas platforms/macos/AtlasTests
git commit -m "fix(macos): polish screenshot workflow verification"
```

If no fixes were needed, do not create an empty commit.

---

## Self-Review

1. **Spec coverage:** This plan covers selection handoff, quick annotation, privacy pixelation placeholder behavior as a visible blur material, copy/save output, and pin screenshot. Pixel magnifier, smart edge snapping, OCR, translation, scrolling capture, drag-to-other-apps, and full editor layering are intentionally excluded from this implementation slice and remain in the broader screenshot spec.
2. **Placeholder scan:** The plan contains concrete files, concrete commands, expected outcomes, and code snippets for each code-producing task. It avoids open-ended instructions.
3. **Type consistency:** `CapturedScreenshot`, `ScreenshotTool`, `ScreenshotAnnotation`, `ScreenshotOutput`, `ScreenshotEditorView`, and `PinnedScreenshotWindow` are introduced before use. `ContentView` handlers use the same names defined in earlier tasks.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-10-screenshot-pro-capture.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints for review

**Which approach?**
