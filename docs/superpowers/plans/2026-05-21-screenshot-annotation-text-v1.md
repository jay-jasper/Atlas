# Screenshot Annotation Text v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users choose the text used by screenshot text annotations instead of always inserting the fixed string `Text`.

**Architecture:** Keep the change in the macOS screenshot editor layer. Add a small value type in `ScreenshotModels.swift` to own text annotation draft trimming and fallback behavior, then bind that model to a compact text field in `ScreenshotEditorView` that only appears when the Text tool is selected.

**Tech Stack:** SwiftUI, AppKit, XCTest, existing Atlas macOS Xcode project.

---

## Scope

This plan implements custom text annotation content:

- A testable `ScreenshotTextAnnotationDraft` model.
- A toolbar text field that appears when `ScreenshotTool.text` is selected.
- Text annotations created from the current draft value.
- Empty or whitespace-only draft text falls back to `Text`.
- Long draft text is clamped to a fixed maximum length so the editor toolbar remains predictable.

Out of scope for this version:

- Editing an existing text annotation after it has been placed.
- Multi-line text annotation editing.
- Font family, font size, or font weight controls.
- Persisting annotation text defaults across launches.
- Rust or FFI changes.
- Manual UI verification.

## File Structure

- `platforms/macos/Atlas/ScreenshotModels.swift`
  - Add `ScreenshotTextAnnotationDraft`, a focused model for sanitizing the editable text annotation value.
- `platforms/macos/Atlas/ScreenshotEditorView.swift`
  - Add text draft state, show a compact text field for the Text tool, and use the draft value when creating `.text` annotations.
- `platforms/macos/AtlasTests/ScreenshotModelsTests.swift`
  - Add unit tests for default text, trimming, whitespace fallback, and length clamping.
- `docs/superpowers/plans/2026-05-21-screenshot-annotation-text-v1.md`
  - Record plan and final verification notes.

---

### Task 1: Text Annotation Draft Model

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotModels.swift`
- Modify: `platforms/macos/AtlasTests/ScreenshotModelsTests.swift`

- [x] **Step 1: Add failing tests for text draft behavior**

Append these tests to `platforms/macos/AtlasTests/ScreenshotModelsTests.swift` before `testCapturedScreenshotInitialization()`:

```swift
    func testTextAnnotationDraftDefaultsToText() {
        let draft = ScreenshotTextAnnotationDraft()

        XCTAssertEqual(draft.rawValue, "Text")
        XCTAssertEqual(draft.annotationValue, "Text")
    }

    func testTextAnnotationDraftTrimsAnnotationValue() {
        let draft = ScreenshotTextAnnotationDraft(rawValue: "  Release 1.0  ")

        XCTAssertEqual(draft.rawValue, "  Release 1.0  ")
        XCTAssertEqual(draft.annotationValue, "Release 1.0")
    }

    func testTextAnnotationDraftFallsBackForBlankValues() {
        XCTAssertEqual(ScreenshotTextAnnotationDraft(rawValue: "").annotationValue, "Text")
        XCTAssertEqual(ScreenshotTextAnnotationDraft(rawValue: "   \n\t  ").annotationValue, "Text")
    }

    func testTextAnnotationDraftLimitsLength() {
        let draft = ScreenshotTextAnnotationDraft(rawValue: String(repeating: "A", count: 120))

        XCTAssertEqual(draft.annotationValue.count, ScreenshotTextAnnotationDraft.maximumLength)
        XCTAssertEqual(draft.annotationValue, String(repeating: "A", count: ScreenshotTextAnnotationDraft.maximumLength))
    }
```

- [x] **Step 2: Run the focused model tests and verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotModelsTests
```

Expected: FAIL because `ScreenshotTextAnnotationDraft` does not exist.

- [x] **Step 3: Add the draft model**

Add this code in `platforms/macos/Atlas/ScreenshotModels.swift` after `ScreenshotAnnotationStyle` and before `ScreenshotAnnotationKind`:

```swift
struct ScreenshotTextAnnotationDraft: Equatable {
    static let fallbackValue = "Text"
    static let maximumLength = 80

    var rawValue: String

    var annotationValue: String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.fallbackValue }
        return String(trimmed.prefix(Self.maximumLength))
    }

    init(rawValue: String = Self.fallbackValue) {
        self.rawValue = rawValue
    }
}
```

- [x] **Step 4: Run the focused model tests and verify pass**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotModelsTests
```

Expected: PASS. The suite should include the new text draft tests plus the existing screenshot model tests.

- [x] **Step 5: Commit Task 1**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotModels.swift platforms/macos/AtlasTests/ScreenshotModelsTests.swift
git commit -m "feat(macos): add screenshot text annotation draft"
```

---

### Task 2: Editor Text Tool Input

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotEditorView.swift`

- [x] **Step 1: Add draft state**

In `platforms/macos/Atlas/ScreenshotEditorView.swift`, add this state property below `annotationLineWidth`:

```swift
    @State private var textAnnotationDraft = ScreenshotTextAnnotationDraft()
```

- [x] **Step 2: Add a compact text field to the annotation toolbar**

In `toolbar`, inside the `if capabilities.annotations { ... }` block, insert this code immediately after the line-width `Stepper`:

```swift
                if selectedTool == .text {
                    TextField("Text", text: $textAnnotationDraft.rawValue)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 96)
                        .help("Text Annotation")
                }
```

The toolbar should still hide all annotation controls when `capabilities.annotations` is false.

- [x] **Step 3: Use the draft value when creating text annotations**

In `annotationDrag`, replace the `.text` case:

```swift
                case .text:
                    annotations.append(.text(value: "Text", rect: rect.width > 8 && rect.height > 8 ? rect : CGRect(x: start.x, y: start.y, width: 80, height: 28), color: style.color))
```

with:

```swift
                case .text:
                    annotations.append(.text(
                        value: textAnnotationDraft.annotationValue,
                        rect: rect.width > 8 && rect.height > 8 ? rect : CGRect(x: start.x, y: start.y, width: 80, height: 28),
                        color: style.color
                    ))
```

- [x] **Step 4: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [x] **Step 5: Run focused screenshot editor tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotModelsTests -only-testing:AtlasTests/ScreenshotEditorRendererTests
```

Expected: PASS. This verifies the new text draft model and confirms existing text annotation rendering still works.

- [x] **Step 6: Commit Task 2**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotEditorView.swift
git commit -m "feat(macos): use custom screenshot text annotations"
```

---

### Task 3: Final Verification and Plan Notes

**Files:**
- Modify: `docs/superpowers/plans/2026-05-21-screenshot-annotation-text-v1.md`

- [x] **Step 1: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [x] **Step 2: Run focused tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotModelsTests -only-testing:AtlasTests/ScreenshotEditorRendererTests
```

Expected: PASS.

- [x] **Step 3: Run full macOS tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected: PASS. Existing non-blocking CoreSimulator warnings may appear; they do not block this macOS unit test run if `TEST SUCCEEDED` appears.

- [x] **Step 4: Append verification notes**

---

## Verification Notes

Completed on 2026-05-21 in `/tmp/atlas-screenshot-annotation-text-v1`.

- Expected failing test: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotModelsTests` failed before implementation because `ScreenshotTextAnnotationDraft` did not exist.
- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift` passed with no output.
- Focused tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotModelsTests -only-testing:AtlasTests/ScreenshotEditorRendererTests` passed with 17 tests and 0 failures.
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'` passed with 142 tests and 0 failures.
- Non-blocking environment warnings: Xcode reported CoreSimulator is out of date (`1051.50.0` older than build version `1051.54.0`) and disabled simulator device support; xcodebuild also warned it was using the first of two matching macOS destinations (`arm64` and `x86_64` My Mac). Both macOS test runs still ended with `** TEST SUCCEEDED **`.

- [x] **Step 5: Commit Task 3**

Run:

```bash
git add docs/superpowers/plans/2026-05-21-screenshot-annotation-text-v1.md
git commit -m "docs: plan screenshot annotation text v1"
```

---

## Self-Review

1. **Spec coverage:** This plan covers the user-visible gap in current text annotations: the value is no longer hardcoded to `Text`, while empty input preserves the current default. It keeps the change scoped to the existing editor and model layer.
2. **Placeholder scan:** The implementation steps include exact file paths, code snippets, commands, expected results, and commit messages. The only bracketed placeholders are in Task 3 verification notes and are explicitly required to be replaced with real command output before committing.
3. **Type consistency:** `ScreenshotTextAnnotationDraft`, `fallbackValue`, `maximumLength`, `rawValue`, and `annotationValue` are defined in Task 1 before Task 2 references them.
