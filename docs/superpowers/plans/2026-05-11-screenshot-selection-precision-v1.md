# Screenshot Selection Precision v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade area screenshot selection with Shottr/WeChat-style precision tools: stable geometry, keyboard nudge, cursor probe, magnifier, and color readout.

**Architecture:** Keep the existing screenshot capture modes and editor intact. Extract selection math and pixel probing into pure Swift helpers with unit tests, then make `SelectionOverlay` consume those helpers. `ScreenshotSelectionWindow` optionally receives a full-screen preview image so the overlay can show a magnifier/color probe without calling live capture APIs from the SwiftUI view.

**Tech Stack:** SwiftUI, AppKit `NSImage` / `NSBitmapImageRep`, XCTest, existing macOS screenshot capture bridge.

---

## Scope Check

This plan covers only area-selection precision:

- Move selection geometry math into testable helpers.
- Add keyboard arrow nudge for existing selections.
- Add Shift+Arrow larger nudge.
- Add Return capture and Escape cancel through one keyboard bridge.
- Add a cursor probe model with pixel coordinate and hex color.
- Add a magnifier/probe overlay backed by an optional full-screen preview image.
- Update `ScreenshotSelectionWindow` / `ContentView` to provide that preview image.

This plan does not implement OCR, translation, scrolling capture, GIF recording, a full preferences screen, multi-display stitching, or new screenshot editor annotation tools.

## File Structure

- Create: `platforms/macos/Atlas/SelectionGeometry.swift`
  - Pure rect normalization, clamping, movement, nudge step, and size labels.
- Create: `platforms/macos/Atlas/SelectionPixelProbe.swift`
  - Pure bitmap-backed color probing and hex formatting.
- Create: `platforms/macos/Atlas/SelectionKeyboardBridge.swift`
  - AppKit `NSViewRepresentable` that forwards key commands to SwiftUI.
- Modify: `platforms/macos/Atlas/SelectionOverlay.swift`
  - Uses `SelectionGeometry`.
  - Shows preview image behind dim overlay when available.
  - Tracks cursor location.
  - Shows magnifier/color probe.
  - Handles keyboard commands.
- Modify: `platforms/macos/Atlas/ScreenshotSelectionWindow.swift`
  - Accepts optional `previewImageData` and passes it into `SelectionOverlay`.
- Modify: `platforms/macos/Atlas/ContentView.swift`
  - Captures a full-screen preview before showing area selection, falling back to no preview on failure.
- Test: `platforms/macos/AtlasTests/SelectionGeometryTests.swift`
  - Unit tests for geometry helpers.
- Test: `platforms/macos/AtlasTests/SelectionPixelProbeTests.swift`
  - Unit tests for color sampling and hex formatting.
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new source and test files.
- Modify: `docs/superpowers/plans/2026-05-11-screenshot-selection-precision-v1.md`
  - Records execution verification.

---

### Task 1: Selection Geometry Helpers

**Files:**
- Create: `platforms/macos/Atlas/SelectionGeometry.swift`
- Create: `platforms/macos/AtlasTests/SelectionGeometryTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write geometry tests**

Create `platforms/macos/AtlasTests/SelectionGeometryTests.swift`:

```swift
import XCTest
@testable import Atlas

final class SelectionGeometryTests: XCTestCase {
    func testNormalizedRectStandardizesAndIntegralizes() {
        let rect = SelectionGeometry.normalizedRect(
            from: CGPoint(x: 20.2, y: 30.8),
            to: CGPoint(x: 5.7, y: 10.1)
        )

        XCTAssertEqual(rect, CGRect(x: 5, y: 10, width: 15, height: 21))
    }

    func testClampPointKeepsPointInsideBounds() {
        let point = SelectionGeometry.clamp(
            CGPoint(x: -5, y: 120),
            bounds: CGSize(width: 100, height: 80)
        )

        XCTAssertEqual(point, CGPoint(x: 0, y: 80))
    }

    func testClampRectKeepsRectInsideBounds() {
        let rect = SelectionGeometry.clamp(
            CGRect(x: 90, y: -10, width: 30, height: 20),
            bounds: CGSize(width: 100, height: 80)
        )

        XCTAssertEqual(rect, CGRect(x: 70, y: 0, width: 30, height: 20))
    }

    func testMoveOffsetsAndClampsRect() {
        let rect = SelectionGeometry.move(
            CGRect(x: 10, y: 10, width: 30, height: 20),
            by: CGSize(width: 80, height: 70),
            bounds: CGSize(width: 100, height: 80)
        )

        XCTAssertEqual(rect, CGRect(x: 70, y: 60, width: 30, height: 20))
    }

    func testNudgeUsesOnePixelOrTenPixels() {
        XCTAssertEqual(SelectionGeometry.nudgeDelta(.left, isLargeStep: false), CGSize(width: -1, height: 0))
        XCTAssertEqual(SelectionGeometry.nudgeDelta(.right, isLargeStep: true), CGSize(width: 10, height: 0))
        XCTAssertEqual(SelectionGeometry.nudgeDelta(.up, isLargeStep: false), CGSize(width: 0, height: -1))
        XCTAssertEqual(SelectionGeometry.nudgeDelta(.down, isLargeStep: true), CGSize(width: 0, height: 10))
    }

    func testSizeLabelUsesIntegralDimensions() {
        XCTAssertEqual(
            SelectionGeometry.sizeLabel(for: CGRect(x: 0, y: 0, width: 99.6, height: 40.2)),
            "100 x 40"
        )
    }
}
```

- [ ] **Step 2: Run geometry tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/SelectionGeometryTests
```

Expected: FAIL because `SelectionGeometry` does not exist or the test file is not in the project yet.

- [ ] **Step 3: Add geometry implementation**

Create `platforms/macos/Atlas/SelectionGeometry.swift`:

```swift
import CoreGraphics

enum SelectionNudgeDirection {
    case left
    case right
    case up
    case down
}

enum SelectionGeometry {
    static let minimumSelectionSize: CGFloat = 8

    static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        ).integral
    }

    static func clamp(_ point: CGPoint, bounds: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), bounds.width),
            y: min(max(0, point.y), bounds.height)
        )
    }

    static func clamp(_ rect: CGRect, bounds: CGSize) -> CGRect {
        CGRect(
            x: min(max(0, rect.minX), max(0, bounds.width - rect.width)),
            y: min(max(0, rect.minY), max(0, bounds.height - rect.height)),
            width: rect.width,
            height: rect.height
        ).integral
    }

    static func move(_ rect: CGRect, by delta: CGSize, bounds: CGSize) -> CGRect {
        clamp(rect.offsetBy(dx: delta.width, dy: delta.height), bounds: bounds)
    }

    static func nudgeDelta(_ direction: SelectionNudgeDirection, isLargeStep: Bool) -> CGSize {
        let step: CGFloat = isLargeStep ? 10 : 1
        switch direction {
        case .left:
            return CGSize(width: -step, height: 0)
        case .right:
            return CGSize(width: step, height: 0)
        case .up:
            return CGSize(width: 0, height: -step)
        case .down:
            return CGSize(width: 0, height: step)
        }
    }

    static func isValidSelection(_ rect: CGRect) -> Bool {
        rect.width >= minimumSelectionSize && rect.height >= minimumSelectionSize
    }

    static func sizeLabel(for rect: CGRect) -> String {
        "\(Int(rect.integral.width)) x \(Int(rect.integral.height))"
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so:

- `SelectionGeometry.swift` is in the `Atlas` target Sources.
- `SelectionGeometryTests.swift` is in the `AtlasTests` target Sources.

- [ ] **Step 5: Run geometry tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/SelectionGeometryTests
```

Expected: PASS, 6 tests.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/SelectionGeometry.swift \
  platforms/macos/AtlasTests/SelectionGeometryTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add selection geometry helpers"
```

---

### Task 2: Pixel Probe Helper

**Files:**
- Create: `platforms/macos/Atlas/SelectionPixelProbe.swift`
- Create: `platforms/macos/AtlasTests/SelectionPixelProbeTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write pixel probe tests**

Create `platforms/macos/AtlasTests/SelectionPixelProbeTests.swift`:

```swift
import AppKit
import XCTest
@testable import Atlas

final class SelectionPixelProbeTests: XCTestCase {
    func testHexColorFormatsRGBComponents() {
        XCTAssertEqual(SelectionPixelProbe.hexColor(red: 255, green: 8, blue: 16), "#FF0810")
    }

    func testProbeSamplesBitmapColor() throws {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        NSColor.green.setFill()
        NSRect(x: 1, y: 0, width: 1, height: 1).fill()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 1, width: 1, height: 1).fill()
        NSColor.white.setFill()
        NSRect(x: 1, y: 1, width: 1, height: 1).fill()
        image.unlockFocus()

        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let probe = SelectionPixelProbe.probe(
            bitmap: bitmap,
            point: CGPoint(x: 1, y: 1),
            viewSize: CGSize(width: 2, height: 2)
        )

        XCTAssertEqual(probe?.pixel, CGPoint(x: 1, y: 1))
        XCTAssertEqual(probe?.hexColor, "#FFFFFF")
    }

    func testProbeReturnsNilOutsideBitmap() throws {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()

        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertNil(SelectionPixelProbe.probe(
            bitmap: bitmap,
            point: CGPoint(x: 20, y: 20),
            viewSize: CGSize(width: 10, height: 10)
        ))
    }
}
```

- [ ] **Step 2: Run pixel probe tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/SelectionPixelProbeTests
```

Expected: FAIL because `SelectionPixelProbe` does not exist or the test file is not in the project yet.

- [ ] **Step 3: Add pixel probe implementation**

Create `platforms/macos/Atlas/SelectionPixelProbe.swift`:

```swift
import AppKit

struct SelectionProbeInfo: Equatable {
    let pixel: CGPoint
    let hexColor: String
}

enum SelectionPixelProbe {
    static func probe(
        bitmap: NSBitmapImageRep,
        point: CGPoint,
        viewSize: CGSize
    ) -> SelectionProbeInfo? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }

        let pixelX = Int((point.x / viewSize.width) * CGFloat(bitmap.pixelsWide))
        let pixelY = Int((point.y / viewSize.height) * CGFloat(bitmap.pixelsHigh))

        guard pixelX >= 0, pixelX < bitmap.pixelsWide, pixelY >= 0, pixelY < bitmap.pixelsHigh else {
            return nil
        }

        guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB) else {
            return nil
        }

        let red = UInt8((color.redComponent * 255).rounded())
        let green = UInt8((color.greenComponent * 255).rounded())
        let blue = UInt8((color.blueComponent * 255).rounded())

        return SelectionProbeInfo(
            pixel: CGPoint(x: pixelX, y: pixelY),
            hexColor: hexColor(red: red, green: green, blue: blue)
        )
    }

    static func hexColor(red: UInt8, green: UInt8, blue: UInt8) -> String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so:

- `SelectionPixelProbe.swift` is in the `Atlas` target Sources.
- `SelectionPixelProbeTests.swift` is in the `AtlasTests` target Sources.

- [ ] **Step 5: Run pixel probe tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/SelectionPixelProbeTests
```

Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/SelectionPixelProbe.swift \
  platforms/macos/AtlasTests/SelectionPixelProbeTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add selection pixel probe"
```

---

### Task 3: Keyboard Command Bridge

**Files:**
- Create: `platforms/macos/Atlas/SelectionKeyboardBridge.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add keyboard bridge implementation**

Create `platforms/macos/Atlas/SelectionKeyboardBridge.swift`:

```swift
import AppKit
import SwiftUI

enum SelectionKeyboardCommand: Equatable {
    case capture
    case cancel
    case nudge(SelectionNudgeDirection, isLargeStep: Bool)
}

struct SelectionKeyboardBridge: NSViewRepresentable {
    let onCommand: (SelectionKeyboardCommand) -> Void

    func makeNSView(context: Context) -> KeyHandlingView {
        let view = KeyHandlingView()
        view.onCommand = onCommand
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyHandlingView, context: Context) {
        nsView.onCommand = onCommand
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class KeyHandlingView: NSView {
        var onCommand: ((SelectionKeyboardCommand) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let isLargeStep = event.modifierFlags.contains(.shift)

            switch event.keyCode {
            case 36:
                onCommand?(.capture)
            case 53:
                onCommand?(.cancel)
            case 123:
                onCommand?(.nudge(.left, isLargeStep: isLargeStep))
            case 124:
                onCommand?(.nudge(.right, isLargeStep: isLargeStep))
            case 125:
                onCommand?(.nudge(.down, isLargeStep: isLargeStep))
            case 126:
                onCommand?(.nudge(.up, isLargeStep: isLargeStep))
            default:
                super.keyDown(with: event)
            }
        }
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `SelectionKeyboardBridge.swift` is in the `Atlas` target Sources.

- [ ] **Step 3: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add platforms/macos/Atlas/SelectionKeyboardBridge.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add selection keyboard bridge"
```

---

### Task 4: Precision Selection Overlay

**Files:**
- Modify: `platforms/macos/Atlas/SelectionOverlay.swift`

- [ ] **Step 1: Replace overlay with precision-aware implementation**

Replace `platforms/macos/Atlas/SelectionOverlay.swift` with:

```swift
import AppKit
import SwiftUI

struct SelectionOverlay: View {
    private enum DragMode {
        case drawing
        case moving(CGRect)
        case resizing(CGRect, Handle)
    }

    private enum Handle: CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    @State private var selection: CGRect?
    @State private var dragMode: DragMode?
    @State private var cursorLocation: CGPoint = .zero

    let previewImageData: Data?
    var onCancel: () -> Void = {}
    var onCapture: (CGRect) -> Void

    init(
        previewImageData: Data? = nil,
        onCancel: @escaping () -> Void = {},
        onCapture: @escaping (CGRect) -> Void
    ) {
        self.previewImageData = previewImageData
        self.onCancel = onCancel
        self.onCapture = onCapture
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                previewLayer
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(backgroundDrag(in: geometry.size))
                    .onContinuousHover { phase in
                        if case .active(let location) = phase {
                            cursorLocation = SelectionGeometry.clamp(location, bounds: geometry.size)
                        }
                    }

                if let rect = selection {
                    selectionView(rect, bounds: geometry.size)
                }

                probeView(bounds: geometry.size)
                    .offset(probeOffset(bounds: geometry.size))

                SelectionKeyboardBridge { command in
                    handleKeyboard(command, bounds: geometry.size)
                }
                .frame(width: 0, height: 0)
            }
        }
    }

    @ViewBuilder
    private var previewLayer: some View {
        if let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .scaledToFill()
        } else {
            Color.clear
        }
    }

    private var previewImage: NSImage? {
        previewImageData.flatMap(NSImage.init(data:))
    }

    private var previewBitmap: NSBitmapImageRep? {
        guard let previewImageData else { return nil }
        return NSBitmapImageRep(data: previewImageData)
    }

    private func selectionView(_ rect: CGRect, bounds: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 2)
                )
                .background(Color.white.opacity(0.04))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .gesture(moveDrag(bounds: bounds))

            ForEach(Handle.allCases, id: \.self) { handle in
                handleView(handle, rect: rect, bounds: bounds)
            }

            sizeBadge(rect)
                .offset(x: rect.minX, y: max(8, rect.minY - 30))

            toolbar(rect, bounds: bounds)
        }
    }

    private func sizeBadge(_ rect: CGRect) -> some View {
        Text(SelectionGeometry.sizeLabel(for: rect))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.78))
            .cornerRadius(5)
    }

    private func toolbar(_ rect: CGRect, bounds: CGSize) -> some View {
        HStack(spacing: 8) {
            Button(action: cancel) {
                Image(systemName: "xmark")
            }
            .help("Cancel")

            Button(action: { capture(rect) }) {
                Image(systemName: "checkmark")
            }
            .help("Capture")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .padding(6)
        .background(.regularMaterial)
        .cornerRadius(8)
        .offset(toolbarOffset(for: rect, bounds: bounds))
    }

    private func toolbarOffset(for rect: CGRect, bounds: CGSize) -> CGSize {
        let x = min(max(8, rect.maxX - 88), max(8, bounds.width - 96))
        let preferredY = rect.maxY + 8
        let y = preferredY + 44 < bounds.height ? preferredY : max(8, rect.minY - 44)
        return CGSize(width: x, height: y)
    }

    private func handleView(_ handle: Handle, rect: CGRect, bounds: CGSize) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 12, height: 12)
            .offset(handleOffset(handle, rect: rect))
            .gesture(resizeDrag(handle: handle, bounds: bounds))
    }

    private func handleOffset(_ handle: Handle, rect: CGRect) -> CGSize {
        let point: CGPoint
        switch handle {
        case .topLeft:
            point = CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            point = CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            point = CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            point = CGPoint(x: rect.maxX, y: rect.maxY)
        }
        return CGSize(width: point.x - 6, height: point.y - 6)
    }

    @ViewBuilder
    private func probeView(bounds: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let previewImage {
                magnifier(previewImage: previewImage, bounds: bounds)
            }

            HStack(spacing: 8) {
                Text("\(Int(cursorLocation.x)), \(Int(cursorLocation.y))")
                if let probe = currentProbe(bounds: bounds) {
                    Circle()
                        .fill(Color(nsColor: NSColor(hex: probe.hexColor) ?? .white))
                        .frame(width: 10, height: 10)
                    Text(probe.hexColor)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
        }
        .padding(8)
        .background(Color.black.opacity(0.78))
        .cornerRadius(8)
    }

    private func magnifier(previewImage: NSImage, bounds: CGSize) -> some View {
        Image(nsImage: previewImage)
            .resizable()
            .scaledToFill()
            .frame(width: bounds.width, height: bounds.height)
            .scaleEffect(3, anchor: .topLeading)
            .offset(x: -cursorLocation.x * 3 + 54, y: -cursorLocation.y * 3 + 54)
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
            .overlay(
                Crosshair()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
    }

    private func currentProbe(bounds: CGSize) -> SelectionProbeInfo? {
        guard let previewBitmap else { return nil }
        return SelectionPixelProbe.probe(
            bitmap: previewBitmap,
            point: cursorLocation,
            viewSize: bounds
        )
    }

    private func probeOffset(bounds: CGSize) -> CGSize {
        let x = cursorLocation.x + 18
        let y = cursorLocation.y + 18
        return CGSize(
            width: x + 140 < bounds.width ? x : max(8, cursorLocation.x - 158),
            height: y + 160 < bounds.height ? y : max(8, cursorLocation.y - 178)
        )
    }

    private func backgroundDrag(in bounds: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                cursorLocation = SelectionGeometry.clamp(value.location, bounds: bounds)
                if dragMode == nil {
                    dragMode = .drawing
                }

                guard case .drawing = dragMode else { return }

                selection = SelectionGeometry.normalizedRect(
                    from: SelectionGeometry.clamp(value.startLocation, bounds: bounds),
                    to: SelectionGeometry.clamp(value.location, bounds: bounds)
                )
            }
            .onEnded { value in
                guard case .drawing = dragMode else { return }

                let rect = SelectionGeometry.normalizedRect(
                    from: SelectionGeometry.clamp(value.startLocation, bounds: bounds),
                    to: SelectionGeometry.clamp(value.location, bounds: bounds)
                )
                selection = SelectionGeometry.isValidSelection(rect) ? rect : nil
                dragMode = nil
            }
    }

    private func moveDrag(bounds: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                cursorLocation = SelectionGeometry.clamp(value.location, bounds: bounds)
                guard let current = selection else { return }

                let originRect: CGRect
                if case let .moving(rect) = dragMode {
                    originRect = rect
                } else {
                    originRect = current
                    dragMode = .moving(current)
                }

                selection = SelectionGeometry.move(
                    originRect,
                    by: value.translation,
                    bounds: bounds
                )
            }
            .onEnded { _ in dragMode = nil }
    }

    private func resizeDrag(handle: Handle, bounds: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                cursorLocation = SelectionGeometry.clamp(value.location, bounds: bounds)
                guard let current = selection else { return }

                let originRect: CGRect
                if case let .resizing(rect, activeHandle) = dragMode, activeHandle == handle {
                    originRect = rect
                } else {
                    originRect = current
                    dragMode = .resizing(current, handle)
                }

                selection = resized(
                    originRect,
                    handle: handle,
                    translation: value.translation,
                    bounds: bounds
                )
            }
            .onEnded { _ in dragMode = nil }
    }

    private func resized(
        _ rect: CGRect,
        handle: Handle,
        translation: CGSize,
        bounds: CGSize
    ) -> CGRect {
        var start: CGPoint
        var end: CGPoint

        switch handle {
        case .topLeft:
            start = CGPoint(x: rect.maxX, y: rect.maxY)
            end = CGPoint(x: rect.minX + translation.width, y: rect.minY + translation.height)
        case .topRight:
            start = CGPoint(x: rect.minX, y: rect.maxY)
            end = CGPoint(x: rect.maxX + translation.width, y: rect.minY + translation.height)
        case .bottomLeft:
            start = CGPoint(x: rect.maxX, y: rect.minY)
            end = CGPoint(x: rect.minX + translation.width, y: rect.maxY + translation.height)
        case .bottomRight:
            start = CGPoint(x: rect.minX, y: rect.minY)
            end = CGPoint(x: rect.maxX + translation.width, y: rect.maxY + translation.height)
        }

        start = SelectionGeometry.clamp(start, bounds: bounds)
        end = SelectionGeometry.clamp(end, bounds: bounds)

        let rect = SelectionGeometry.normalizedRect(from: start, to: end)
        return SelectionGeometry.isValidSelection(rect) ? rect : selection ?? rect
    }

    private func handleKeyboard(_ command: SelectionKeyboardCommand, bounds: CGSize) {
        switch command {
        case .capture:
            if let selection {
                capture(selection)
            }
        case .cancel:
            cancel()
        case .nudge(let direction, let isLargeStep):
            guard let selection else { return }
            self.selection = SelectionGeometry.move(
                selection,
                by: SelectionGeometry.nudgeDelta(direction, isLargeStep: isLargeStep),
                bounds: bounds
            )
        }
    }

    private func capture(_ rect: CGRect) {
        onCapture(rect.integral)
    }

    private func cancel() {
        selection = nil
        dragMode = nil
        onCancel()
    }
}

private struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let intValue = Int(value, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((intValue >> 16) & 0xff) / 255,
            green: CGFloat((intValue >> 8) & 0xff) / 255,
            blue: CGFloat(intValue & 0xff) / 255,
            alpha: 1
        )
    }
}

#Preview {
    SelectionOverlay(onCancel: {}) { rect in
        print("Captured: \(rect)")
    }
}
```

- [ ] **Step 2: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [ ] **Step 3: Run selection helper tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' \
  -only-testing:AtlasTests/SelectionGeometryTests \
  -only-testing:AtlasTests/SelectionPixelProbeTests
```

Expected: PASS, 9 tests.

- [ ] **Step 4: Commit**

```bash
git add platforms/macos/Atlas/SelectionOverlay.swift
git commit -m "feat(macos): add precision selection overlay"
```

---

### Task 5: Selection Preview Injection

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotSelectionWindow.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Update selection window API**

In `platforms/macos/Atlas/ScreenshotSelectionWindow.swift`, replace the `show` signature:

```swift
static func show(onCancel: @escaping () -> Void = {}, onCapture: @escaping (CGRect) -> Void) {
```

with:

```swift
static func show(
    previewImageData: Data? = nil,
    onCancel: @escaping () -> Void = {},
    onCapture: @escaping (CGRect) -> Void
) {
```

Replace the call to `showOnMain` inside `show` with:

```swift
showOnMain(previewImageData: previewImageData, onCancel: onCancel, onCapture: onCapture)
```

Replace the async branch with:

```swift
DispatchQueue.main.async {
    showOnMain(previewImageData: previewImageData, onCancel: onCancel, onCapture: onCapture)
}
```

Replace the private `showOnMain` signature:

```swift
private static func showOnMain(onCancel: @escaping () -> Void, onCapture: @escaping (CGRect) -> Void) {
```

with:

```swift
private static func showOnMain(
    previewImageData: Data?,
    onCancel: @escaping () -> Void,
    onCapture: @escaping (CGRect) -> Void
) {
```

Replace the `SelectionOverlay` construction with:

```swift
let overlay = SelectionOverlay(
    previewImageData: previewImageData,
    onCancel: {
        close()
        onCancel()
    },
    onCapture: { rect in
        close()
        onCapture(rect)
    }
)
```

- [ ] **Step 2: Update ContentView to provide a preview**

In `platforms/macos/Atlas/ContentView.swift`, replace:

```swift
private func showSelectionWindow() {
    ScreenshotSelectionWindow.show(onCapture: captureSelection)
}
```

with:

```swift
private func showSelectionWindow() {
    let previewData = try? AtlasBridge.captureFullScreen()
    ScreenshotSelectionWindow.show(
        previewImageData: previewData,
        onCapture: captureSelection
    )
}
```

- [ ] **Step 3: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [ ] **Step 4: Build app**

Run:

```bash
xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotSelectionWindow.swift \
  platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): provide screenshot preview to selection overlay"
```

---

### Task 6: Final Verification Notes

**Files:**
- Modify: `docs/superpowers/plans/2026-05-11-screenshot-selection-precision-v1.md`

- [ ] **Step 1: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [ ] **Step 2: Run focused tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' \
  -only-testing:AtlasTests/SelectionGeometryTests \
  -only-testing:AtlasTests/SelectionPixelProbeTests
```

Expected: PASS.

- [ ] **Step 3: Run full Xcode tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 4: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-11-screenshot-selection-precision-v1.md`:

```markdown
## Execution Verification Notes

- Swift parse:
  - `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - Result: PASS
- Focused Xcode tests:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/SelectionGeometryTests -only-testing:AtlasTests/SelectionPixelProbeTests`
  - Result: PASS
- Full Xcode tests:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: PASS
- Manual:
  - Manual screenshot selection verification was not performed. On 2026-05-11, user acceptance criteria for these task plans is automated/unit tests passing.
- Remaining limitations:
  - Magnifier preview is based on a full-screen snapshot taken before the selection overlay opens.
  - Pixel probing assumes the preview image is scaled to the overlay bounds.
  - Multi-display coordinate stitching is not included in this slice.
```

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-05-11-screenshot-selection-precision-v1.md
git commit -m "docs: record screenshot selection precision verification"
```

---

## Execution Verification Notes

- Swift parse:
  - `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - Result: PASS
- Focused Xcode tests:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/SelectionGeometryTests -only-testing:AtlasTests/SelectionPixelProbeTests`
  - Result: PASS, 10 tests, 0 failures
- Full Xcode tests:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: PASS, 60 tests, 0 failures
- Manual:
  - Manual screenshot selection verification was not performed. The current acceptance gate is unit tests passing.
- Remaining limitations:
  - Magnifier preview is based on a full-screen snapshot taken before the selection overlay opens.
  - Pixel probing assumes the preview image is scaled to the overlay bounds.
  - Multi-display coordinate stitching is not included in this slice.

---

## Self-Review

1. **Spec coverage:** This plan advances the area screenshot flow toward Shottr/WeChat behavior by adding tested geometry, keyboard nudge, Return/Escape handling, cursor coordinates, magnifier, and color probe. Existing desktop/window/area capture modes and editor output flow remain intact.
2. **Placeholder scan:** The plan contains concrete file paths, code, commands, expected results, and commit messages. It does not include TBD/TODO placeholders or unspecified implementation steps.
3. **Type consistency:** `SelectionGeometry`, `SelectionNudgeDirection`, `SelectionPixelProbe`, `SelectionProbeInfo`, `SelectionKeyboardCommand`, and `SelectionKeyboardBridge` are defined before `SelectionOverlay` references them. `ScreenshotSelectionWindow.show(previewImageData:onCancel:onCapture:)` is defined before `ContentView.showSelectionWindow()` calls it.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-11-screenshot-selection-precision-v1.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
