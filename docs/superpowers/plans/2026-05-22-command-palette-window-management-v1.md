# Command Palette Window Management v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add window management commands to the Atlas command palette for moving the frontmost window to common layouts.

**Architecture:** Add a small window-management service boundary plus a command palette provider. The service owns window actions and pure frame calculations; the provider only maps searchable commands to `PaletteCommand`. Accessibility-dependent code stays behind `WindowManaging` so unit tests never require real macOS Accessibility permissions.

**Tech Stack:** Swift, SwiftUI command palette models, AppKit, macOS Accessibility APIs, XCTest, Xcode project file updates via `xcodeproj`.

---

## Scope

This plan implements command palette actions for the currently focused window:

- Center frontmost window.
- Move frontmost window to left half.
- Move frontmost window to right half.
- Maximize frontmost window to the visible screen frame.

Out of scope:

- Arbitrary window tiling grids.
- Multi-display selection UI.
- User-configurable shortcuts.
- Persisted window layout history.
- Manual Accessibility permission onboarding UI.
- Any command palette UI redesign.

## File Map

**New files:**

- `platforms/macos/Atlas/WindowManagementService.swift`
  - Defines `WindowManagementAction`, `WindowManaging`, `WindowFrameCalculator`, and `AccessibilityWindowManager`.
  - Keeps geometry calculations pure and deterministic.
  - Wraps AX focused-window mutation behind a protocol.

- `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift`
  - Implements `CommandProviding`.
  - Owns the fixed command list and maps each command to a `WindowManagementAction`.

- `platforms/macos/AtlasTests/WindowManagementServiceTests.swift`
  - Tests pure frame calculation for center, left half, right half, and maximize.

- `platforms/macos/AtlasTests/WindowManagementProviderTests.swift`
  - Tests provider search, metadata, action dispatch, result cap, and blank query behavior.

**Modified files:**

- `platforms/macos/Atlas/AtlasApp.swift`
  - Registers `WindowManagementProvider` after `DeveloperToolsProvider` and before `ClipboardHistoryProvider`.

- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds the two source files to the `Atlas` target and the two test files to the `AtlasTests` target.

---

## Task 1: Window Management Service

**Files:**
- Create: `platforms/macos/Atlas/WindowManagementService.swift`
- Create: `platforms/macos/AtlasTests/WindowManagementServiceTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing service tests**

Create `platforms/macos/AtlasTests/WindowManagementServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class WindowManagementServiceTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testLeftHalfFrameUsesVisibleScreenLeftHalf() {
        let frame = WindowFrameCalculator.frame(
            for: .leftHalf,
            currentFrame: CGRect(x: 400, y: 200, width: 500, height: 300),
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    func testRightHalfFrameUsesVisibleScreenRightHalf() {
        let frame = WindowFrameCalculator.frame(
            for: .rightHalf,
            currentFrame: CGRect(x: 400, y: 200, width: 500, height: 300),
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, CGRect(x: 720, y: 0, width: 720, height: 900))
    }

    func testMaximizeFrameUsesVisibleScreenFrame() {
        let frame = WindowFrameCalculator.frame(
            for: .maximize,
            currentFrame: CGRect(x: 400, y: 200, width: 500, height: 300),
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, screen)
    }

    func testCenterFrameKeepsCurrentSizeAndCentersInVisibleScreen() {
        let frame = WindowFrameCalculator.frame(
            for: .center,
            currentFrame: CGRect(x: 20, y: 30, width: 600, height: 400),
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, CGRect(x: 420, y: 250, width: 600, height: 400))
    }

    func testCenterFrameClampsOversizedWindowToVisibleScreen() {
        let frame = WindowFrameCalculator.frame(
            for: .center,
            currentFrame: CGRect(x: 20, y: 30, width: 2000, height: 1200),
            visibleScreenFrame: screen
        )

        XCTAssertEqual(frame, screen)
    }

    func testActionTitlesAreStable() {
        XCTAssertEqual(WindowManagementAction.center.title, "Center Frontmost Window")
        XCTAssertEqual(WindowManagementAction.leftHalf.title, "Move Frontmost Window Left Half")
        XCTAssertEqual(WindowManagementAction.rightHalf.title, "Move Frontmost Window Right Half")
        XCTAssertEqual(WindowManagementAction.maximize.title, "Maximize Frontmost Window")
    }
}
```

- [ ] **Step 2: Add the test file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
unless group.files.any? { |f| f.path == 'WindowManagementServiceTests.swift' }
  ref = group.new_file('WindowManagementServiceTests.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 3: Run the service tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/WindowManagementServiceTests
```

Expected: compile failure mentioning missing `WindowFrameCalculator` and `WindowManagementAction`.

- [ ] **Step 4: Write the service implementation**

Create `platforms/macos/Atlas/WindowManagementService.swift`:

```swift
import AppKit
import ApplicationServices
import Foundation

enum WindowManagementAction: CaseIterable, Equatable {
    case center
    case leftHalf
    case rightHalf
    case maximize

    var title: String {
        switch self {
        case .center:
            return "Center Frontmost Window"
        case .leftHalf:
            return "Move Frontmost Window Left Half"
        case .rightHalf:
            return "Move Frontmost Window Right Half"
        case .maximize:
            return "Maximize Frontmost Window"
        }
    }

    var keywords: [String] {
        switch self {
        case .center:
            return ["window", "manage", "center", "frontmost"]
        case .leftHalf:
            return ["window", "manage", "left", "half", "tile", "frontmost"]
        case .rightHalf:
            return ["window", "manage", "right", "half", "tile", "frontmost"]
        case .maximize:
            return ["window", "manage", "maximize", "full", "frontmost"]
        }
    }
}

protocol WindowManaging {
    @discardableResult
    func perform(_ action: WindowManagementAction) -> Bool
}

enum WindowFrameCalculator {
    static func frame(
        for action: WindowManagementAction,
        currentFrame: CGRect,
        visibleScreenFrame: CGRect
    ) -> CGRect {
        switch action {
        case .center:
            let width = min(currentFrame.width, visibleScreenFrame.width)
            let height = min(currentFrame.height, visibleScreenFrame.height)
            let x = visibleScreenFrame.minX + (visibleScreenFrame.width - width) / 2
            let y = visibleScreenFrame.minY + (visibleScreenFrame.height - height) / 2
            return CGRect(x: x, y: y, width: width, height: height).integral
        case .leftHalf:
            return CGRect(
                x: visibleScreenFrame.minX,
                y: visibleScreenFrame.minY,
                width: visibleScreenFrame.width / 2,
                height: visibleScreenFrame.height
            ).integral
        case .rightHalf:
            return CGRect(
                x: visibleScreenFrame.midX,
                y: visibleScreenFrame.minY,
                width: visibleScreenFrame.width / 2,
                height: visibleScreenFrame.height
            ).integral
        case .maximize:
            return visibleScreenFrame.integral
        }
    }
}

final class AccessibilityWindowManager: WindowManaging {
    @discardableResult
    func perform(_ action: WindowManagementAction) -> Bool {
        guard
            let window = focusedWindow(),
            let currentFrame = frame(of: window),
            let screenFrame = NSScreen.main?.visibleFrame
        else {
            return false
        }

        let targetFrame = WindowFrameCalculator.frame(
            for: action,
            currentFrame: currentFrame,
            visibleScreenFrame: screenFrame
        )
        return setFrame(targetFrame, for: window)
    }

    private func focusedWindow() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard
            let position = cgPointAttribute(kAXPositionAttribute, from: window),
            let size = cgSizeAttribute(kAXSizeAttribute, from: window)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) -> Bool {
        var position = frame.origin
        var size = frame.size

        guard
            let positionValue = AXValueCreate(.cgPoint, &position),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            return false
        }

        let positionResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )
        let sizeResult = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        return positionResult == .success && sizeResult == .success
    }

    private func cgPointAttribute(_ attribute: String, from window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, attribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue((axValue as! AXValue), .cgPoint, &point) else { return nil }
        return point
    }

    private func cgSizeAttribute(_ attribute: String, from window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, attribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue((axValue as! AXValue), .cgSize, &size) else { return nil }
        return size
    }
}
```

- [ ] **Step 5: Add the service file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']
unless group.files.any? { |f| f.path == 'WindowManagementService.swift' }
  ref = group.new_file('WindowManagementService.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 6: Run the service tests to verify they pass**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/WindowManagementServiceTests
```

Expected: `WindowManagementServiceTests` passes with 6 tests and 0 failures.

- [ ] **Step 7: Commit**

Run:

```bash
git add platforms/macos/Atlas/WindowManagementService.swift \
        platforms/macos/AtlasTests/WindowManagementServiceTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add window management service"
```

---

## Task 2: Window Management Provider

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift`
- Create: `platforms/macos/AtlasTests/WindowManagementProviderTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing provider tests**

Create `platforms/macos/AtlasTests/WindowManagementProviderTests.swift`:

```swift
import XCTest
@testable import Atlas

final class WindowManagementProviderTests: XCTestCase {
    func testEmptyQueryReturnsNoResults() {
        let provider = makeProvider()

        XCTAssertTrue(provider.results(for: " \n ").isEmpty)
    }

    func testWindowQueryReturnsWindowManagementCommands() {
        let provider = makeProvider()
        let results = provider.results(for: "window")

        XCTAssertEqual(results.map(\.title), [
            "Center Frontmost Window",
            "Move Frontmost Window Left Half",
            "Move Frontmost Window Right Half",
            "Maximize Frontmost Window",
        ])
    }

    func testLeftQueryMatchesLeftHalfCommand() {
        let provider = makeProvider()
        let results = provider.results(for: "left")

        XCTAssertEqual(results.map(\.title), ["Move Frontmost Window Left Half"])
    }

    func testRightQueryMatchesRightHalfCommand() {
        let provider = makeProvider()
        let results = provider.results(for: "right")

        XCTAssertEqual(results.map(\.title), ["Move Frontmost Window Right Half"])
    }

    func testMaximizeQueryMatchesMaximizeCommand() {
        let provider = makeProvider()
        let results = provider.results(for: "maximize")

        XCTAssertEqual(results.map(\.title), ["Maximize Frontmost Window"])
    }

    func testAllResultsHaveWindowCategoryAndIcon() {
        let provider = makeProvider()
        let results = provider.results(for: "window")

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.category == "Window" })
        XCTAssertTrue(results.allSatisfy { $0.icon == .sfSymbol("rectangle.inset.filled") })
    }

    func testExecutingResultPerformsInjectedAction() {
        let manager = RecordingWindowManager()
        let provider = WindowManagementProvider(windowManager: manager)

        let result = provider.results(for: "left").first
        if case .execute(let execute)? = result?.action {
            execute()
        } else {
            XCTFail("expected executable window management result")
        }

        XCTAssertEqual(manager.performedActions, [.leftHalf])
    }

    func testResultsAreCappedToFive() {
        let provider = makeProvider()
        let results = provider.results(for: "window")

        XCTAssertLessThanOrEqual(results.count, 5)
    }

    private func makeProvider() -> WindowManagementProvider {
        WindowManagementProvider(windowManager: RecordingWindowManager())
    }
}

private final class RecordingWindowManager: WindowManaging {
    private(set) var performedActions: [WindowManagementAction] = []

    @discardableResult
    func perform(_ action: WindowManagementAction) -> Bool {
        performedActions.append(action)
        return true
    }
}
```

- [ ] **Step 2: Add the test file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
unless group.files.any? { |f| f.path == 'WindowManagementProviderTests.swift' }
  ref = group.new_file('WindowManagementProviderTests.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 3: Run the provider tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/WindowManagementProviderTests
```

Expected: compile failure mentioning missing `WindowManagementProvider`.

- [ ] **Step 4: Write the provider implementation**

Create `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift`:

```swift
import Foundation

final class WindowManagementProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let windowManager: WindowManaging
    private let actions: [WindowManagementAction]

    init(
        windowManager: WindowManaging = AccessibilityWindowManager(),
        actions: [WindowManagementAction] = WindowManagementAction.allCases
    ) {
        self.windowManager = windowManager
        self.actions = actions
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return actions
            .filter { action in
                action.title.localizedCaseInsensitiveContains(q) ||
                action.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
            }
            .prefix(Self.maxResultsCount)
            .map { action in
                PaletteCommand(
                    id: UUID(),
                    title: action.title,
                    subtitle: nil,
                    icon: .sfSymbol("rectangle.inset.filled"),
                    keywords: action.keywords,
                    action: .execute { [windowManager] in
                        _ = windowManager.perform(action)
                    },
                    category: "Window"
                )
            }
    }
}
```

- [ ] **Step 5: Add the provider file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']['CommandPalette']
unless group.files.any? { |f| f.path == 'WindowManagementProvider.swift' }
  ref = group.new_file('WindowManagementProvider.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 6: Run provider and service tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/WindowManagementProviderTests \
  -only-testing:AtlasTests/WindowManagementServiceTests
```

Expected: both test classes pass with 14 tests and 0 failures.

- [ ] **Step 7: Commit**

Run:

```bash
git add platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift \
        platforms/macos/AtlasTests/WindowManagementProviderTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add command palette window management provider"
```

---

## Task 3: Register Provider and Verify

**Files:**
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Test: `platforms/macos/AtlasTests/WindowManagementProviderTests.swift`
- Test: `platforms/macos/AtlasTests/WindowManagementServiceTests.swift`

- [ ] **Step 1: Register `WindowManagementProvider`**

In `platforms/macos/Atlas/AtlasApp.swift`, update `CommandPaletteState.init()` provider construction from:

```swift
let developerToolsProvider = DeveloperToolsProvider()
let clipboardHistoryProvider = ClipboardHistoryProvider()
let appLauncherProvider = AppLauncherProvider()

self.controller = CommandPaletteController(providers: [
    atlasProvider,
    developerToolsProvider,
    clipboardHistoryProvider,
    appLauncherProvider,
])
```

to:

```swift
let developerToolsProvider = DeveloperToolsProvider()
let windowManagementProvider = WindowManagementProvider()
let clipboardHistoryProvider = ClipboardHistoryProvider()
let appLauncherProvider = AppLauncherProvider()

self.controller = CommandPaletteController(providers: [
    atlasProvider,
    developerToolsProvider,
    windowManagementProvider,
    clipboardHistoryProvider,
    appLauncherProvider,
])
```

- [ ] **Step 2: Run focused command palette provider tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/WindowManagementProviderTests \
  -only-testing:AtlasTests/WindowManagementServiceTests \
  -only-testing:AtlasTests/DeveloperToolsProviderTests \
  -only-testing:AtlasTests/ClipboardHistoryProviderTests \
  -only-testing:AtlasTests/AppLauncherProviderTests \
  -only-testing:AtlasTests/AtlasCommandProviderTests
```

Expected: selected tests pass with 47 tests and 0 failures.

- [ ] **Step 3: Run full macOS test suite**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS'
```

Expected: full suite passes. Existing environment warnings about CoreSimulator or `com.apple.linkd.autoShortcut` are non-blocking if the test result ends with `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit registration**

Run:

```bash
git add platforms/macos/Atlas/AtlasApp.swift
git commit -m "feat(macos): register window management commands"
```

---

## Task 4: Record Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-22-command-palette-window-management-v1.md`

- [ ] **Step 1: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-22-command-palette-window-management-v1.md`:

```markdown
## Verification Notes

Completed on 2026-05-22 on branch `codex/command-palette-window-management-v1`.

- Focused provider/service tests:
  - `WindowManagementProviderTests`
  - `WindowManagementServiceTests`
  - `DeveloperToolsProviderTests`
  - `ClipboardHistoryProviderTests`
  - `AppLauncherProviderTests`
  - `AtlasCommandProviderTests`
- Full macOS test suite:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Manual window movement verification was not run; this follows the project preference that unit tests are sufficient unless explicitly requested.
```

- [ ] **Step 2: Commit the plan and verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-command-palette-window-management-v1.md
git commit -m "docs: add command palette window management plan"
```

---

## Self-Review

1. **Spec coverage:** This plan adds a standalone command palette window management provider, registers it, keeps Accessibility work behind `WindowManaging`, and verifies behavior with deterministic unit tests. It does not include any out-of-scope UI redesign, custom shortcuts, or persistent layouts.

2. **Placeholder scan:** The plan contains concrete file paths, exact test code, implementation code, commands, expected results, and commit messages. It contains no undefined placeholder steps.

3. **Type consistency:** `WindowManagementAction`, `WindowManaging`, `WindowFrameCalculator`, `AccessibilityWindowManager`, and `WindowManagementProvider` are introduced before later tasks reference them. Provider tests use the same `WindowManaging.perform(_:)` signature defined in Task 1.

## Verification Notes

Completed on 2026-05-22 on branch `codex/command-palette-window-management-v1`.

- Focused provider/service tests:
  - `WindowManagementProviderTests`
  - `WindowManagementServiceTests`
  - `DeveloperToolsProviderTests`
  - `ClipboardHistoryProviderTests`
  - `AppLauncherProviderTests`
  - `AtlasCommandProviderTests`
- Full macOS test suite:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Manual window movement verification was not run; this follows the project preference that unit tests are sufficient unless explicitly requested.
