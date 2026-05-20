# Screenshot Quick Output Feedback v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit action routing and status feedback for the floating screenshot thumbnail so Copy, Save, Open, and Dismiss have visible, testable outcomes.

**Architecture:** Keep this in the macOS UI layer. Add a tiny value-type action model beside the existing floating thumbnail window, make the SwiftUI thumbnail render status from that model, and adapt `ContentView` callbacks to return action results without changing capture, library, OCR, or translation storage.

**Tech Stack:** SwiftUI, AppKit, XCTest, existing Atlas macOS Xcode project.

---

## Scope

This plan implements Screenshot Quick Output Feedback v1:

- Define stable thumbnail actions: open editor, copy, save, dismiss.
- Define status text for each action result.
- Show a compact status chip inside the floating thumbnail.
- Keep thumbnail quick actions explicit as icon buttons plus context menu actions.
- Route copy/save/open/dismiss through a small result model so behavior can be unit tested.

Out of scope:

- Dragging screenshots into other apps.
- Auto-dismiss timers.
- Screenshot output preferences.
- Screenshot feature toggle changes.
- Rust or UniFFI changes.
- Manual UI verification. The user preference is unit tests only.

## File Structure

- `platforms/macos/Atlas/FloatingScreenshotThumbnailWindow.swift`
  - Add `FloatingScreenshotThumbnailAction`, `FloatingScreenshotThumbnailActionResult`, and `FloatingScreenshotThumbnailActionState`.
  - Update `FloatingScreenshotThumbnailWindow.show` callback signatures to return `FloatingScreenshotThumbnailActionResult`.
  - Update `FloatingScreenshotThumbnailView` to show action buttons and status feedback.
- `platforms/macos/Atlas/ContentView.swift`
  - Add small thumbnail-specific action handlers that wrap existing `copyScreenshot`, `saveScreenshot`, and editor open behavior.
- `platforms/macos/AtlasTests/FloatingScreenshotThumbnailWindowTests.swift`
  - Add unit tests for action metadata and status transitions.
- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - No new files expected. Only touch this if Xcode project structure changes unexpectedly.

---

### Task 1: Thumbnail Action Model

**Files:**
- Modify: `platforms/macos/Atlas/FloatingScreenshotThumbnailWindow.swift`
- Modify: `platforms/macos/AtlasTests/FloatingScreenshotThumbnailWindowTests.swift`

- [ ] **Step 1: Write failing action model tests**

Append these tests to `platforms/macos/AtlasTests/FloatingScreenshotThumbnailWindowTests.swift` before the closing brace:

```swift
    func testThumbnailActionsHaveStableMetadata() {
        XCTAssertEqual(FloatingScreenshotThumbnailAction.allCases, [.open, .copy, .save, .dismiss])
        XCTAssertEqual(FloatingScreenshotThumbnailAction.open.title, "Open Editor")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.open.systemImage, "square.and.pencil")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.copy.title, "Copy")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.copy.systemImage, "doc.on.doc")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.save.title, "Save")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.save.systemImage, "square.and.arrow.down")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.dismiss.title, "Dismiss")
        XCTAssertEqual(FloatingScreenshotThumbnailAction.dismiss.systemImage, "xmark")
    }

    func testActionResultStatusText() {
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.ready.statusText, "Ready")
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.openedEditor.statusText, "Opened editor")
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.copied.statusText, "Copied")
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.saved(filename: "Atlas.png").statusText, "Saved Atlas.png")
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.saveCancelled.statusText, "Save cancelled")
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.dismissed.statusText, "Dismissed")
    }

    func testActionStateAppliesResults() {
        var state = FloatingScreenshotThumbnailActionState()

        XCTAssertEqual(state.statusText, "Ready")
        state.apply(.copied)
        XCTAssertEqual(state.statusText, "Copied")
        state.apply(.saved(filename: "One.png"))
        XCTAssertEqual(state.statusText, "Saved One.png")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests
```

Expected: FAIL because `FloatingScreenshotThumbnailAction`, `FloatingScreenshotThumbnailActionResult`, and `FloatingScreenshotThumbnailActionState` do not exist.

- [ ] **Step 3: Add the action model**

In `platforms/macos/Atlas/FloatingScreenshotThumbnailWindow.swift`, insert this code after the imports and before `FloatingScreenshotThumbnailLayout`:

```swift
enum FloatingScreenshotThumbnailAction: CaseIterable, Equatable {
    case open
    case copy
    case save
    case dismiss

    var title: String {
        switch self {
        case .open:
            return "Open Editor"
        case .copy:
            return "Copy"
        case .save:
            return "Save"
        case .dismiss:
            return "Dismiss"
        }
    }

    var systemImage: String {
        switch self {
        case .open:
            return "square.and.pencil"
        case .copy:
            return "doc.on.doc"
        case .save:
            return "square.and.arrow.down"
        case .dismiss:
            return "xmark"
        }
    }
}

enum FloatingScreenshotThumbnailActionResult: Equatable {
    case ready
    case openedEditor
    case copied
    case saved(filename: String)
    case saveCancelled
    case dismissed

    var statusText: String {
        switch self {
        case .ready:
            return "Ready"
        case .openedEditor:
            return "Opened editor"
        case .copied:
            return "Copied"
        case .saved(let filename):
            return "Saved \(filename)"
        case .saveCancelled:
            return "Save cancelled"
        case .dismissed:
            return "Dismissed"
        }
    }
}

struct FloatingScreenshotThumbnailActionState: Equatable {
    private(set) var result: FloatingScreenshotThumbnailActionResult = .ready

    var statusText: String {
        result.statusText
    }

    mutating func apply(_ result: FloatingScreenshotThumbnailActionResult) {
        self.result = result
    }
}
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests
```

Expected: PASS with 7 tests.

- [ ] **Step 5: Commit action model**

Run:

```bash
git add platforms/macos/Atlas/FloatingScreenshotThumbnailWindow.swift platforms/macos/AtlasTests/FloatingScreenshotThumbnailWindowTests.swift
git commit -m "feat(macos): model screenshot thumbnail actions"
```

---

### Task 2: Thumbnail UI Status Feedback

**Files:**
- Modify: `platforms/macos/Atlas/FloatingScreenshotThumbnailWindow.swift`
- Modify: `platforms/macos/AtlasTests/FloatingScreenshotThumbnailWindowTests.swift`

- [ ] **Step 1: Write failing view model test**

Append this test to `platforms/macos/AtlasTests/FloatingScreenshotThumbnailWindowTests.swift` before the closing brace:

```swift
    func testActionStateStatusTextChangesAfterEachResult() {
        var state = FloatingScreenshotThumbnailActionState()
        let results: [FloatingScreenshotThumbnailActionResult] = [
            .openedEditor,
            .copied,
            .saveCancelled,
            .dismissed,
        ]

        let statuses = results.map { result in
            state.apply(result)
            return state.statusText
        }

        XCTAssertEqual(statuses, [
            "Opened editor",
            "Copied",
            "Save cancelled",
            "Dismissed",
        ])
    }
```

- [ ] **Step 2: Run tests to verify current state**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests
```

Expected: PASS if Task 1 model was implemented correctly. If this fails, fix Task 1 before editing the view.

- [ ] **Step 3: Update callback signatures**

In `FloatingScreenshotThumbnailWindow.show`, change the callback parameters from:

```swift
onOpen: @escaping () -> Void,
onCopy: @escaping (Data) -> Void,
onSave: @escaping (Data) -> Void,
onDismiss: @escaping () -> Void
```

to:

```swift
onOpen: @escaping () -> FloatingScreenshotThumbnailActionResult,
onCopy: @escaping (Data) -> FloatingScreenshotThumbnailActionResult,
onSave: @escaping (Data) -> FloatingScreenshotThumbnailActionResult,
onDismiss: @escaping () -> FloatingScreenshotThumbnailActionResult
```

Make the same signature change in the private `showOnMain` method.

- [ ] **Step 4: Update view construction callbacks**

In `showOnMain`, replace the `FloatingScreenshotThumbnailView` construction callbacks with:

```swift
let view = FloatingScreenshotThumbnailView(
    image: image,
    dimensionsText: "\(Int(screenshot.rect.width)) x \(Int(screenshot.rect.height))",
    onOpen: {
        let result = onOpen()
        dismissOnMain()
        return result
    },
    onCopy: {
        onCopy(screenshot.pngData)
    },
    onSave: {
        onSave(screenshot.pngData)
    },
    onDismiss: {
        let result = onDismiss()
        dismissOnMain()
        return result
    }
)
```

- [ ] **Step 5: Update `FloatingScreenshotThumbnailView` stored properties**

In `FloatingScreenshotThumbnailView`, replace the action closure properties:

```swift
let onOpen: () -> Void
let onCopy: () -> Void
let onSave: () -> Void
let onDismiss: () -> Void
```

with:

```swift
let onOpen: () -> FloatingScreenshotThumbnailActionResult
let onCopy: () -> FloatingScreenshotThumbnailActionResult
let onSave: () -> FloatingScreenshotThumbnailActionResult
let onDismiss: () -> FloatingScreenshotThumbnailActionResult

@State private var actionState = FloatingScreenshotThumbnailActionState()
```

- [ ] **Step 6: Add action execution helper**

Inside `FloatingScreenshotThumbnailView`, add this helper below `body`:

```swift
private func perform(_ action: FloatingScreenshotThumbnailAction) {
    let result: FloatingScreenshotThumbnailActionResult

    switch action {
    case .open:
        result = onOpen()
    case .copy:
        result = onCopy()
    case .save:
        result = onSave()
    case .dismiss:
        result = onDismiss()
    }

    actionState.apply(result)
}
```

- [ ] **Step 7: Replace tap and context menu actions**

In `FloatingScreenshotThumbnailView.body`, replace:

```swift
.onTapGesture(perform: onOpen)
```

with:

```swift
.onTapGesture {
    perform(.open)
}
```

Replace the `contextMenu` block with:

```swift
.contextMenu {
    Button(FloatingScreenshotThumbnailAction.open.title) { perform(.open) }
    Button(FloatingScreenshotThumbnailAction.copy.title) { perform(.copy) }
    Button(FloatingScreenshotThumbnailAction.save.title) { perform(.save) }
    Divider()
    Button(FloatingScreenshotThumbnailAction.dismiss.title) { perform(.dismiss) }
}
```

- [ ] **Step 8: Add visible action controls and status chip**

Inside the main `ZStack`, after the existing dimensions `HStack`, add this overlay content:

```swift
VStack {
    HStack(spacing: 6) {
        ForEach(FloatingScreenshotThumbnailAction.allCases, id: \.self) { action in
            Button {
                perform(action)
            } label: {
                Image(systemName: action.systemImage)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(action.title)
        }
    }
    .padding(6)
    .background(.black.opacity(0.62))
    .cornerRadius(7)

    Spacer()
}
.padding(7)

VStack {
    Spacer()
    HStack {
        Spacer()
        Text(actionState.statusText)
            .font(.caption2)
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.68))
            .cornerRadius(6)
    }
}
.padding(7)
```

Keep the existing top-right dismiss button in place, but change its action from `onDismiss` to:

```swift
perform(.dismiss)
```

- [ ] **Step 9: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [ ] **Step 10: Run focused tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests
```

Expected: PASS with 8 tests.

- [ ] **Step 11: Commit UI status feedback**

Run:

```bash
git add platforms/macos/Atlas/FloatingScreenshotThumbnailWindow.swift platforms/macos/AtlasTests/FloatingScreenshotThumbnailWindowTests.swift
git commit -m "feat(macos): show screenshot thumbnail action feedback"
```

---

### Task 3: ContentView Output Routing

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Update thumbnail routing call**

In `showFloatingThumbnail(for:libraryItemID:)`, replace:

```swift
onOpen: {
    openFloatingThumbnail(screenshot, libraryItemID: libraryItemID)
},
onCopy: copyScreenshot,
onSave: saveScreenshot,
onDismiss: {}
```

with:

```swift
onOpen: {
    openFloatingThumbnail(screenshot, libraryItemID: libraryItemID)
},
onCopy: copyScreenshotFromThumbnail,
onSave: saveScreenshotFromThumbnail,
onDismiss: dismissFloatingThumbnail
```

- [ ] **Step 2: Return action result from open handler**

Change `openFloatingThumbnail` from:

```swift
private func openFloatingThumbnail(_ screenshot: CapturedScreenshot, libraryItemID: UUID?) {
    invalidateScreenshotTextTasks()
    activeLibraryItemID = libraryItemID
    capturedScreenshot = screenshot
    clearScreenshotTextState()
}
```

to:

```swift
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
```

- [ ] **Step 3: Add thumbnail-specific copy/save/dismiss handlers**

Add these methods below `openFloatingThumbnail`:

```swift
private func copyScreenshotFromThumbnail(_ data: Data) -> FloatingScreenshotThumbnailActionResult {
    ScreenshotOutput.copyPNGToClipboard(data)
    showStatus("Copied screenshot")
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
```

Keep the existing `copyScreenshot(_:)` and `saveScreenshot(_:)` methods unchanged because the editor still uses them.

- [ ] **Step 4: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [ ] **Step 5: Run focused tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests
```

Expected: PASS with 8 tests.

- [ ] **Step 6: Commit ContentView routing**

Run:

```bash
git add platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): route screenshot thumbnail output actions"
```

---

### Task 4: Final Verification and Plan Notes

**Files:**
- Modify: `docs/superpowers/plans/2026-05-21-screenshot-quick-output-feedback-v1.md`

- [ ] **Step 1: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [ ] **Step 2: Run focused thumbnail tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests
```

Expected: PASS with 8 tests.

- [ ] **Step 3: Run full macOS tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected: PASS. The existing CoreSimulator out-of-date warning is acceptable if macOS tests run and `TEST SUCCEEDED` appears.

- [ ] **Step 4: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-21-screenshot-quick-output-feedback-v1.md`:

```markdown
---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
- Focused thumbnail tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests`
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`

Screenshot Quick Output Feedback v1 keeps the output workflow local to the macOS UI layer. It adds visible feedback and testable routing without changing capture, library, OCR, or translation persistence.
```

- [ ] **Step 5: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-21-screenshot-quick-output-feedback-v1.md
git commit -m "docs: plan screenshot quick output feedback v1"
```

---

## Self-Review

1. **Spec coverage:** This plan covers the requested next workflow slice after floating thumbnails: explicit quick output actions, status feedback, and testable action routing. It does not cover drag-to-other-apps or output preferences because those are separate workflow subsystems.
2. **Placeholder scan:** No step uses unfinished markers, vague validation, or references to undefined types. All introduced types are defined in Task 1 before later tasks use them.
3. **Type consistency:** `FloatingScreenshotThumbnailAction`, `FloatingScreenshotThumbnailActionResult`, and `FloatingScreenshotThumbnailActionState` names are consistent across tests, view code, and `ContentView` routing.

---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift` passed with no output.
- Focused thumbnail tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests` passed with 8 tests, 0 failures.
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'` passed with 128 tests, 0 failures. The existing CoreSimulator out-of-date warning appeared before the macOS tests ran, and `TEST SUCCEEDED` appeared.

Screenshot Quick Output Feedback v1 keeps the output workflow local to the macOS UI layer. It adds visible feedback and testable routing without changing capture, library, OCR, or translation persistence.
