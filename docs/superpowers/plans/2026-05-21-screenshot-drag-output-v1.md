# Screenshot Drag Output v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users drag the floating screenshot thumbnail into other apps as a PNG file.

**Architecture:** Keep drag export in the macOS UI layer. Add a small drag payload store that writes PNG data to a temporary file and returns an `NSItemProvider`; the floating thumbnail view receives an item-provider factory and attaches it with SwiftUI `.onDrag`.

**Tech Stack:** SwiftUI, AppKit, UniformTypeIdentifiers, Foundation `FileManager`, XCTest, existing Atlas macOS Xcode project.

---

## Scope

This plan implements Screenshot Drag Output v1:

- Generate stable temporary PNG filenames for drag export.
- Write dragged screenshot PNG data to a temporary drag-output directory.
- Return an `NSItemProvider` backed by the temporary PNG file URL.
- Attach drag output to the floating screenshot thumbnail image/background.
- Keep existing Open / Copy / Save / Dismiss behavior unchanged.
- Provide a cleanup method for old drag export files.

Out of scope:

- Dragging edited/annotated screenshot output. This v1 drags the captured PNG currently shown in the thumbnail.
- Auto-cleanup timers.
- Drag previews beyond SwiftUI's default preview.
- User preferences for drag output format.
- Rust or UniFFI changes.
- Manual UI verification. The user preference is unit tests only.

## File Structure

- `platforms/macos/Atlas/ScreenshotDragOutput.swift`
  - Owns `ScreenshotDragOutputItem`, filename generation, temporary file writes, item provider creation, and cleanup of old drag files.
- `platforms/macos/Atlas/FloatingScreenshotThumbnailWindow.swift`
  - Accepts an `onDragItemProvider` closure and attaches `.onDrag` to the image/background layer.
- `platforms/macos/Atlas/ContentView.swift`
  - Owns a `ScreenshotDragOutputStore` instance and passes drag providers to the floating thumbnail.
- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds the new Swift source and test file.
- `platforms/macos/AtlasTests/ScreenshotDragOutputTests.swift`
  - Unit tests for filename generation, file writes, item provider metadata, and cleanup.

---

### Task 1: Drag Output Store

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotDragOutput.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotDragOutputTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing drag output tests**

Create `platforms/macos/AtlasTests/ScreenshotDragOutputTests.swift`:

```swift
import XCTest
import UniformTypeIdentifiers
@testable import Atlas

final class ScreenshotDragOutputTests: XCTestCase {
    private var rootDirectory: URL!
    private var store: ScreenshotDragOutputStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotDragOutputTests-\(UUID().uuidString)", isDirectory: true)
        store = ScreenshotDragOutputStore(rootDirectory: rootDirectory)
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        store = nil
        rootDirectory = nil
        try super.tearDownWithError()
    }

    func testFilenameUsesTimestampAndIdentifier() {
        let filename = ScreenshotDragOutputStore.filename(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            date: Date(timeIntervalSince1970: 1_704_067_200)
        )

        XCTAssertEqual(filename, "Atlas Drag Screenshot 2024-01-01 00.00.00 11111111.png")
    }

    func testMakeDragItemWritesPngFile() throws {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        let item = try store.makeDragItem(
            pngData: Data([0x89, 0x50, 0x4E, 0x47]),
            id: id,
            date: date
        )

        XCTAssertEqual(item.filename, "Atlas Drag Screenshot 2024-01-01 00.00.00 AAAAAAAA.png")
        XCTAssertEqual(item.url.lastPathComponent, item.filename)
        XCTAssertEqual(try Data(contentsOf: item.url), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testMakeItemProviderRegistersFileURLAndPNGType() throws {
        let provider = try store.makeItemProvider(
            pngData: Data([1, 2, 3]),
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            date: Date(timeIntervalSince1970: 1_704_067_200)
        )

        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier))
    }

    func testCleanupRemovesOnlyOldDragFiles() throws {
        let oldItem = try store.makeDragItem(
            pngData: Data([1]),
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            date: Date(timeIntervalSince1970: 10)
        )
        let freshItem = try store.makeDragItem(
            pngData: Data([2]),
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            date: Date(timeIntervalSince1970: 20)
        )
        let unrelatedURL = rootDirectory.appendingPathComponent("manual.txt")
        try Data([3]).write(to: unrelatedURL)

        let oldAttributes: [FileAttributeKey: Any] = [
            .modificationDate: Date(timeIntervalSince1970: 10),
        ]
        let freshAttributes: [FileAttributeKey: Any] = [
            .modificationDate: Date(timeIntervalSince1970: 20),
        ]
        try FileManager.default.setAttributes(oldAttributes, ofItemAtPath: oldItem.url.path)
        try FileManager.default.setAttributes(freshAttributes, ofItemAtPath: freshItem.url.path)

        try store.cleanupFiles(olderThan: Date(timeIntervalSince1970: 15))

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldItem.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshItem.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotDragOutputTests
```

Expected: FAIL because `ScreenshotDragOutputStore` does not exist.

- [ ] **Step 3: Add drag output implementation**

Create `platforms/macos/Atlas/ScreenshotDragOutput.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

struct ScreenshotDragOutputItem: Equatable {
    let url: URL
    let filename: String
}

struct ScreenshotDragOutputStore {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Atlas Screenshot Drag Output", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    static func filename(id: UUID, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let prefix = id.uuidString.split(separator: "-").first.map(String.init) ?? id.uuidString
        return "Atlas Drag Screenshot \(formatter.string(from: date)) \(prefix).png"
    }

    func makeDragItem(
        pngData: Data,
        id: UUID,
        date: Date = Date()
    ) throws -> ScreenshotDragOutputItem {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let filename = Self.filename(id: id, date: date)
        let url = rootDirectory.appendingPathComponent(filename, isDirectory: false)
        try pngData.write(to: url, options: [.atomic])
        return ScreenshotDragOutputItem(url: url, filename: filename)
    }

    func makeItemProvider(
        pngData: Data,
        id: UUID,
        date: Date = Date()
    ) throws -> NSItemProvider {
        let item = try makeDragItem(pngData: pngData, id: id, date: date)
        let provider = NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        provider.suggestedName = item.filename
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(pngData, nil)
            return nil
        }
        return provider
    }

    func cleanupFiles(olderThan cutoffDate: Date) throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }

        let urls = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for url in urls where url.pathExtension.lowercased() == "png" {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let modificationDate = attributes[.modificationDate] as? Date ?? .distantFuture
            if modificationDate < cutoffDate {
                try fileManager.removeItem(at: url)
            }
        }
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Modify `platforms/macos/Atlas.xcodeproj/project.pbxproj` following the existing nearby pattern for `FloatingScreenshotThumbnailWindow.swift` and `FloatingScreenshotThumbnailWindowTests.swift`:

```text
ScreenshotDragOutput.swift
ScreenshotDragOutputTests.swift
```

Add the source file to the `Atlas` target source build phase, and add the test file to the `AtlasTests` target source build phase.

- [ ] **Step 5: Run focused tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotDragOutputTests
```

Expected: PASS with 4 tests.

- [ ] **Step 6: Commit drag output store**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotDragOutput.swift platforms/macos/AtlasTests/ScreenshotDragOutputTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add screenshot drag output store"
```

---

### Task 2: Floating Thumbnail Drag Integration

**Files:**
- Modify: `platforms/macos/Atlas/FloatingScreenshotThumbnailWindow.swift`
- Modify: `platforms/macos/AtlasTests/FloatingScreenshotThumbnailWindowTests.swift`

- [ ] **Step 1: Write failing drag state tests**

Append these tests to `platforms/macos/AtlasTests/FloatingScreenshotThumbnailWindowTests.swift` before the closing brace:

```swift
    func testActionResultDraggedStatusText() {
        XCTAssertEqual(FloatingScreenshotThumbnailActionResult.dragged.statusText, "Ready to drag")
    }

    func testActionStateAppliesDraggedResult() {
        var state = FloatingScreenshotThumbnailActionState()

        state.apply(.dragged)

        XCTAssertEqual(state.statusText, "Ready to drag")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests
```

Expected: FAIL because `FloatingScreenshotThumbnailActionResult.dragged` does not exist.

- [ ] **Step 3: Add dragged action result**

In `platforms/macos/Atlas/FloatingScreenshotThumbnailWindow.swift`, add a new case to `FloatingScreenshotThumbnailActionResult`:

```swift
case dragged
```

Then add this branch in `statusText`:

```swift
case .dragged:
    return "Ready to drag"
```

- [ ] **Step 4: Add item provider closure to window and view**

Update `FloatingScreenshotThumbnailWindow.show` and `showOnMain` signatures by adding:

```swift
onDragItemProvider: @escaping () -> NSItemProvider
```

The final signature should be:

```swift
static func show(
    screenshot: CapturedScreenshot,
    onOpen: @escaping () -> FloatingScreenshotThumbnailActionResult,
    onCopy: @escaping (Data) -> FloatingScreenshotThumbnailActionResult,
    onSave: @escaping (Data) -> FloatingScreenshotThumbnailActionResult,
    onDismiss: @escaping () -> FloatingScreenshotThumbnailActionResult,
    onDragItemProvider: @escaping () -> NSItemProvider
)
```

Pass the new closure through the main-thread async call and the private `showOnMain` method.

In the `FloatingScreenshotThumbnailView` construction, add:

```swift
onDragItemProvider: onDragItemProvider
```

Update `FloatingScreenshotThumbnailView` stored properties by adding:

```swift
let onDragItemProvider: () -> NSItemProvider
```

- [ ] **Step 5: Attach `.onDrag` to image/background layer**

In `FloatingScreenshotThumbnailView.body`, on the image/background view that already has `.onTapGesture`, add:

```swift
.onDrag {
    actionState.apply(.dragged)
    return onDragItemProvider()
}
```

The image chain should include both tap and drag:

```swift
Image(nsImage: image)
    .resizable()
    .scaledToFit()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .contentShape(Rectangle())
    .onTapGesture {
        perform(.open)
    }
    .onDrag {
        actionState.apply(.dragged)
        return onDragItemProvider()
    }
```

- [ ] **Step 6: Run focused thumbnail tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests
```

Expected: PASS with 10 tests.

- [ ] **Step 7: Commit thumbnail drag integration**

Run:

```bash
git add platforms/macos/Atlas/FloatingScreenshotThumbnailWindow.swift platforms/macos/AtlasTests/FloatingScreenshotThumbnailWindowTests.swift
git commit -m "feat(macos): enable floating thumbnail drag"
```

---

### Task 3: ContentView Drag Provider Wiring

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Add drag output store**

In `ContentView`, below the existing `screenshotLibraryStore` property:

```swift
private let screenshotDragOutputStore = ScreenshotDragOutputStore()
```

- [ ] **Step 2: Pass drag provider into thumbnail window**

In `showFloatingThumbnail(for:libraryItemID:)`, update the `FloatingScreenshotThumbnailWindow.show` call from:

```swift
FloatingScreenshotThumbnailWindow.show(
    screenshot: screenshot,
    onOpen: {
        openFloatingThumbnail(screenshot, libraryItemID: libraryItemID)
    },
    onCopy: copyScreenshotFromThumbnail,
    onSave: saveScreenshotFromThumbnail,
    onDismiss: dismissFloatingThumbnail
)
```

to:

```swift
FloatingScreenshotThumbnailWindow.show(
    screenshot: screenshot,
    onOpen: {
        openFloatingThumbnail(screenshot, libraryItemID: libraryItemID)
    },
    onCopy: copyScreenshotFromThumbnail,
    onSave: saveScreenshotFromThumbnail,
    onDismiss: dismissFloatingThumbnail,
    onDragItemProvider: {
        dragItemProvider(for: screenshot)
    }
)
```

- [ ] **Step 3: Add drag item provider helper**

Add this method below `dismissFloatingThumbnail()`:

```swift
private func dragItemProvider(for screenshot: CapturedScreenshot) -> NSItemProvider {
    do {
        return try screenshotDragOutputStore.makeItemProvider(
            pngData: screenshot.pngData,
            id: screenshot.id,
            date: screenshot.capturedAt
        )
    } catch {
        showStatus(error.localizedDescription, kind: .error)
        return NSItemProvider()
    }
}
```

- [ ] **Step 4: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [ ] **Step 5: Run drag output and thumbnail tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotDragOutputTests -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests
```

Expected: PASS with 14 tests.

- [ ] **Step 6: Commit ContentView drag wiring**

Run:

```bash
git add platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): wire screenshot thumbnail drag output"
```

---

### Task 4: Drag Output Cleanup

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotDragOutput.swift`
- Modify: `platforms/macos/AtlasTests/ScreenshotDragOutputTests.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Write cleanup cutoff test**

Append this test to `platforms/macos/AtlasTests/ScreenshotDragOutputTests.swift` before the closing brace:

```swift
    func testCleanupCutoffForDefaultRetention() {
        let now = Date(timeIntervalSince1970: 86_400 * 3)
        let cutoff = ScreenshotDragOutputStore.cleanupCutoff(now: now)

        XCTAssertEqual(cutoff, Date(timeIntervalSince1970: 86_400 * 2))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotDragOutputTests
```

Expected: FAIL because `cleanupCutoff(now:)` does not exist.

- [ ] **Step 3: Add cleanup cutoff helper**

In `ScreenshotDragOutputStore`, add this static method below `filename(id:date:)`:

```swift
static func cleanupCutoff(now: Date = Date()) -> Date {
    now.addingTimeInterval(-86_400)
}
```

- [ ] **Step 4: Add startup cleanup call**

In `ContentView.startModules()`, after:

```swift
loadScreenshotLibrary()
```

add:

```swift
cleanupScreenshotDragOutput()
```

Then add this method below `loadScreenshotLibrary()`:

```swift
private func cleanupScreenshotDragOutput() {
    do {
        try screenshotDragOutputStore.cleanupFiles(
            olderThan: ScreenshotDragOutputStore.cleanupCutoff()
        )
    } catch {
        showStatus(error.localizedDescription, kind: .error, autoHide: false)
    }
}
```

- [ ] **Step 5: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [ ] **Step 6: Run focused tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotDragOutputTests
```

Expected: PASS with 5 tests.

- [ ] **Step 7: Commit cleanup**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotDragOutput.swift platforms/macos/AtlasTests/ScreenshotDragOutputTests.swift platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): clean up screenshot drag files"
```

---

### Task 5: Final Verification and Plan Notes

**Files:**
- Modify: `docs/superpowers/plans/2026-05-21-screenshot-drag-output-v1.md`

- [x] **Step 1: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [x] **Step 2: Run focused drag tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotDragOutputTests -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests
```

Expected: PASS.

- [x] **Step 3: Run full macOS tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected: PASS. The existing CoreSimulator out-of-date warning is acceptable if macOS tests run and `TEST SUCCEEDED` appears.

- [x] **Step 4: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-21-screenshot-drag-output-v1.md`:

```markdown
---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
- Focused drag tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotDragOutputTests -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests`
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`

Screenshot Drag Output v1 writes temporary PNG files for cross-app drag operations and registers an `NSItemProvider` with both file URL and PNG representations. Cleanup removes old generated PNG files from the drag-output directory on app startup.
```

- [x] **Step 5: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-21-screenshot-drag-output-v1.md
git commit -m "docs: plan screenshot drag output v1"
```

---

## Self-Review

1. **Spec coverage:** The plan covers thumbnail drag output, temporary PNG file generation, item provider registration, ContentView wiring, and cleanup. It intentionally excludes edited screenshot dragging and manual UI verification.
2. **Placeholder scan:** No step uses unfinished markers, vague validation, or references to undefined types. All new types are introduced before later tasks use them.
3. **Type consistency:** `ScreenshotDragOutputStore`, `ScreenshotDragOutputItem`, `makeDragItem`, `makeItemProvider`, and `cleanupFiles` names are consistent across implementation, tests, and ContentView wiring.

---

## Verification Notes

Task 5 completed on 2026-05-21 in `/tmp/atlas-screenshot-drag-output-v1`.

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - Result: PASS, exit code 0, no output.
- Focused drag tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotDragOutputTests -only-testing:AtlasTests/FloatingScreenshotThumbnailWindowTests`
  - Result: PASS, `TEST SUCCEEDED`.
  - Tests: 15 executed, 0 failures. `FloatingScreenshotThumbnailWindowTests`: 10 tests. `ScreenshotDragOutputTests`: 5 tests.
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: PASS, `TEST SUCCEEDED`.
  - Tests: 135 executed, 0 failures.
- Non-blocking warnings observed during both `xcodebuild` runs:
  - CoreSimulator was out of date, so simulator device support was disabled. macOS tests still ran on `platform=macOS`.
  - Xcode reported multiple matching macOS destinations and used the first destination.

Screenshot Drag Output v1 writes temporary PNG files for cross-app drag operations and registers an `NSItemProvider` with both file URL and PNG representations. Cleanup removes old generated PNG files from the drag-output directory on app startup.
