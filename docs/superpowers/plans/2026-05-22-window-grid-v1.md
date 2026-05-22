# Window Grid v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Feature Center gated 3x3 window grid panel that moves the active window into selected grid cells.

**Architecture:** Extend the existing Swift-only window management boundary instead of adding Rust or UniFFI work. Keep Accessibility-dependent focused-window mutation behind `WindowManaging`, keep grid math pure in `WindowFrameCalculator`, and inject window manager state into SwiftUI tests so tests never need real Accessibility permission or real windows.

**Tech Stack:** Swift, SwiftUI, AppKit Accessibility APIs, XCTest, explicit Xcode PBX project membership via `xcodeproj`.

---

## Scope

This plan implements:

- A 3x3 grid UI in the Atlas menu bar panel.
- Active frontmost window targeting through the existing Accessibility window manager.
- Accessibility permission status and request handling before grid actions mutate windows.
- Multi-display coordinate mapping by reusing the focused window's current display.
- Feature Center gating through the existing `window-manager` feature flag.
- Tests with injected window manager state and injected Accessibility permission state.

Out of scope:

- Persisted workspaces.
- User configurable grid dimensions.
- Drag-to-select grid cells larger than one cell.
- Keyboard shortcuts for individual grid cells.

## Current Baseline

`platforms/macos/Atlas/WindowManagementService.swift` already defines:

- `WindowManagementAction.center`, `.leftHalf`, `.rightHalf`, and `.maximize`.
- `WindowManaging.perform(_:)`.
- Pure `WindowFrameCalculator.frame(for:currentFrame:visibleScreenFrame:)`.
- `WindowCoordinateConverter` for AppKit and AX coordinate conversion.
- `AccessibilityWindowManager` that mutates the focused frontmost window.

`platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift` already exposes command palette actions for the fixed window actions. Existing tests are in `platforms/macos/AtlasTests/WindowManagementServiceTests.swift` and `platforms/macos/AtlasTests/WindowManagementProviderTests.swift`.

## File Map

**New files:**

- `platforms/macos/Atlas/WindowGridPanel.swift`
  - SwiftUI 3x3 grid panel.
  - Shows Accessibility status.
  - Calls injected `WindowManaging` only when the feature is enabled and Accessibility is trusted.

- `platforms/macos/Atlas/WindowManagementPermissions.swift`
  - Defines `WindowManagementPermissionChecking`.
  - Provides live AppKit implementation using `AXIsProcessTrusted()` and `AXIsProcessTrustedWithOptions`.

- `platforms/macos/AtlasTests/WindowGridPanelTests.swift`
  - Tests grid labels, disabled feature behavior, permission request behavior, and injected manager actions.

**Modified files:**

- `platforms/macos/Atlas/WindowManagementService.swift`
  - Adds `WindowGridPosition`.
  - Adds `.grid(WindowGridPosition)` to `WindowManagementAction`.
  - Adds pure frame calculation for 3x3 positions.

- `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift`
  - Keeps existing actions.
  - Accepts an `isEnabled` closure so command palette window management results disappear when `window-manager` is disabled.

- `platforms/macos/Atlas/AtlasModule.swift`
  - Adds `case windowManager = "window-manager"`.
  - Adds title `Window Manager`.

- `platforms/macos/Atlas/FeatureModels.swift`
  - Maps `window-manager` to `AtlasModule.windowManager.title`.

- `platforms/macos/Atlas/AtlasApp.swift`
  - Owns one shared `AccessibilityWindowManager` and one shared `AccessibilityPermissionChecker`.
  - Injects the shared window manager into `CommandPaletteState` and `ContentView`.
  - Injects the shared permission checker into `ContentView`.
  - Lets `CommandPaletteState` update window management gating from `ContentView`.

- `platforms/macos/Atlas/ContentView.swift`
  - Shows `WindowGridPanel` only when `AtlasModule.windowManager` is enabled.
  - Updates command palette gating when Feature Center toggles `window-manager`.

- `platforms/macos/AtlasTests/WindowManagementServiceTests.swift`
  - Adds pure grid frame and multi-display coordinate tests.

- `platforms/macos/AtlasTests/WindowManagementProviderTests.swift`
  - Adds provider gating tests.

- `platforms/macos/AtlasTests/FeatureModelsTests.swift`
  - Adds `window-manager` title mapping test.

- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new Swift app files to the `Atlas` target sources.
  - Adds new Swift test files to the `AtlasTests` target sources.

---

### Task 1: Feature Center Mapping for Window Manager

**Files:**
- Modify: `platforms/macos/Atlas/AtlasModule.swift`
- Modify: `platforms/macos/Atlas/FeatureModels.swift`
- Test: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

- [x] **Step 1: Add the failing title mapping test**

Append this test inside `FeatureModelsTests` in `platforms/macos/AtlasTests/FeatureModelsTests.swift`:

```swift
func testWindowManagerFeatureUsesAtlasModuleTitle() {
    let feature = AtlasFeature(name: "window-manager", isEnabled: false)

    XCTAssertEqual(feature.title, "Window Manager")
}
```

- [x] **Step 2: Run the feature model test and verify it fails**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureModelsTests
```

Expected: FAIL because `AtlasModule.windowManager` is not defined or `window-manager` still falls through to the default title mapping.

- [x] **Step 3: Add the window manager module**

Replace `platforms/macos/Atlas/AtlasModule.swift` with:

```swift
enum AtlasModule: String, CaseIterable, Identifiable {
    case screenshot
    case monitoring
    case windowManager = "window-manager"

    var id: String { rawValue }

    var featureName: String {
        rawValue
    }

    var title: String {
        switch self {
        case .screenshot:
            return "Screenshot"
        case .monitoring:
            return "Monitoring"
        case .windowManager:
            return "Window Manager"
        }
    }
}
```

- [x] **Step 4: Map the title explicitly**

In `platforms/macos/Atlas/FeatureModels.swift`, replace the `switch name` body in `AtlasFeatureTitles.title(for:)` with:

```swift
switch name {
case AtlasModule.monitoring.featureName:
    return AtlasModule.monitoring.title
case AtlasModule.screenshot.featureName:
    return AtlasModule.screenshot.title
case AtlasModule.windowManager.featureName:
    return AtlasModule.windowManager.title
default:
    return name
        .split(separator: "-")
        .map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }
        .joined(separator: " ")
}
```

- [x] **Step 5: Run the feature model test and verify it passes**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureModelsTests
```

Expected: PASS.

---

### Task 2: Grid Frame Calculation

**Files:**
- Modify: `platforms/macos/Atlas/WindowManagementService.swift`
- Test: `platforms/macos/AtlasTests/WindowManagementServiceTests.swift`

- [x] **Step 1: Add failing grid tests**

Append these tests inside `WindowManagementServiceTests` in `platforms/macos/AtlasTests/WindowManagementServiceTests.swift`:

```swift
func testGridTopLeftUsesOneThirdOfVisibleScreen() {
    let frame = WindowFrameCalculator.frame(
        for: .grid(WindowGridPosition(row: 0, column: 0)),
        currentFrame: .zero,
        visibleScreenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
    )

    XCTAssertEqual(frame, CGRect(x: 0, y: 600, width: 480, height: 300))
}

func testGridCenterUsesMiddleCell() {
    let frame = WindowFrameCalculator.frame(
        for: .grid(WindowGridPosition(row: 1, column: 1)),
        currentFrame: .zero,
        visibleScreenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
    )

    XCTAssertEqual(frame, CGRect(x: 480, y: 300, width: 480, height: 300))
}

func testGridBottomRightUsesDisplayOriginAndIntegralFrame() {
    let frame = WindowFrameCalculator.frame(
        for: .grid(WindowGridPosition(row: 2, column: 2)),
        currentFrame: .zero,
        visibleScreenFrame: CGRect(x: 200, y: 50, width: 1_440, height: 900)
    )

    XCTAssertEqual(frame, CGRect(x: 1_160, y: 50, width: 480, height: 300))
}

func testGridPositionClampsInvalidInputToGridBounds() {
    XCTAssertEqual(WindowGridPosition(row: -1, column: 9), WindowGridPosition(row: 0, column: 2))
}
```

- [x] **Step 2: Run the grid tests and verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WindowManagementServiceTests
```

Expected: FAIL because `WindowGridPosition` and `WindowManagementAction.grid` do not exist yet.

- [x] **Step 3: Extend the action model and frame calculator**

In `platforms/macos/Atlas/WindowManagementService.swift`, replace `WindowManagementAction` and `WindowFrameCalculator` with:

```swift
struct WindowGridPosition: Equatable, Hashable {
    let row: Int
    let column: Int

    init(row: Int, column: Int) {
        self.row = min(max(row, 0), 2)
        self.column = min(max(column, 0), 2)
    }

    var titleSuffix: String {
        let vertical: String
        switch row {
        case 0: vertical = "Top"
        case 1: vertical = "Middle"
        default: vertical = "Bottom"
        }

        let horizontal: String
        switch column {
        case 0: horizontal = "Left"
        case 1: horizontal = "Center"
        default: horizontal = "Right"
        }

        return "\(vertical) \(horizontal)"
    }
}

enum WindowManagementAction: Equatable {
    case center
    case leftHalf
    case rightHalf
    case maximize
    case grid(WindowGridPosition)

    static let commandPaletteActions: [WindowManagementAction] = [
        .center,
        .leftHalf,
        .rightHalf,
        .maximize,
    ]

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
        case .grid(let position):
            return "Move Frontmost Window \(position.titleSuffix)"
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
        case .grid(let position):
            return ["window", "manage", "grid", "tile", "frontmost", position.titleSuffix]
        }
    }
}

enum WindowFrameCalculator {
    static func frame(
        for action: WindowManagementAction,
        currentFrame: CGRect,
        visibleScreenFrame: CGRect
    ) -> CGRect {
        switch action {
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
        case .center:
            let width = min(currentFrame.width, visibleScreenFrame.width)
            let height = min(currentFrame.height, visibleScreenFrame.height)
            return CGRect(
                x: visibleScreenFrame.minX + (visibleScreenFrame.width - width) / 2,
                y: visibleScreenFrame.minY + (visibleScreenFrame.height - height) / 2,
                width: width,
                height: height
            ).integral
        case .grid(let position):
            let cellWidth = visibleScreenFrame.width / 3
            let cellHeight = visibleScreenFrame.height / 3
            return CGRect(
                x: visibleScreenFrame.minX + CGFloat(position.column) * cellWidth,
                y: visibleScreenFrame.maxY - CGFloat(position.row + 1) * cellHeight,
                width: cellWidth,
                height: cellHeight
            ).integral
        }
    }
}
```

- [x] **Step 4: Update provider default actions**

In `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift`, change the initializer default from:

```swift
actions: [WindowManagementAction] = WindowManagementAction.allCases
```

to:

```swift
actions: [WindowManagementAction] = WindowManagementAction.commandPaletteActions
```

- [x] **Step 5: Run window management tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WindowManagementServiceTests -only-testing:AtlasTests/WindowManagementProviderTests
```

Expected: PASS.

---

### Task 3: Accessibility Permission Boundary

**Files:**
- Create: `platforms/macos/Atlas/WindowManagementPermissions.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
- Test through: `platforms/macos/AtlasTests/WindowGridPanelTests.swift` in Task 5

- [x] **Step 1: Create the permission checker**

Create `platforms/macos/Atlas/WindowManagementPermissions.swift`:

```swift
import ApplicationServices
import Foundation

protocol WindowManagementPermissionChecking {
    var isTrusted: Bool { get }
    func requestPermission()
}

struct AccessibilityPermissionChecker: WindowManagementPermissionChecking {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
```

- [x] **Step 2: Add the file to the Xcode project**

Run this exact script from the repository root:

```bash
ruby <<'RUBY'
require 'xcodeproj'

project_path = 'platforms/macos/Atlas.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |target| target.name == 'Atlas' }
atlas_group = project.main_group['Atlas']

abort('Atlas target not found') unless app_target
abort('Atlas group not found') unless atlas_group

path = 'WindowManagementPermissions.swift'
unless atlas_group.files.any? { |file| file.path == path }
  file_ref = atlas_group.new_file(path)
  app_target.add_file_references([file_ref])
end

project.save
RUBY
```

- [x] **Step 3: Verify the permission file builds**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WindowManagementServiceTests
```

Expected: PASS.

---

### Task 4: Command Palette Feature Gating

**Files:**
- Modify: `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift`
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Test: `platforms/macos/AtlasTests/WindowManagementProviderTests.swift`

- [x] **Step 1: Add failing provider gating tests**

Append these tests inside `WindowManagementProviderTests`:

```swift
func testDisabledProviderReturnsNoWindowResults() {
    let provider = makeProvider(isEnabled: { false })

    XCTAssertTrue(provider.results(for: "window").isEmpty)
}

func testEnabledProviderReturnsWindowResults() {
    let provider = makeProvider(isEnabled: { true })

    XCTAssertFalse(provider.results(for: "window").isEmpty)
}
```

Update the `makeProvider` helper to:

```swift
private func makeProvider(
    windowManager: WindowManaging = FakeWindowManager(),
    actions: [WindowManagementAction] = WindowManagementAction.commandPaletteActions,
    isEnabled: @escaping () -> Bool = { true }
) -> WindowManagementProvider {
    WindowManagementProvider(
        windowManager: windowManager,
        actions: actions,
        isEnabled: isEnabled
    )
}
```

- [x] **Step 2: Run provider tests and verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WindowManagementProviderTests
```

Expected: FAIL because `WindowManagementProvider` has no `isEnabled` initializer parameter.

- [x] **Step 3: Gate provider results**

Replace `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift` with:

```swift
import Foundation

final class WindowManagementProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let windowManager: WindowManaging
    private let actions: [WindowManagementAction]
    private let isEnabled: () -> Bool

    init(
        windowManager: WindowManaging = AccessibilityWindowManager(),
        actions: [WindowManagementAction] = WindowManagementAction.commandPaletteActions,
        isEnabled: @escaping () -> Bool = { true }
    ) {
        self.windowManager = windowManager
        self.actions = actions
        self.isEnabled = isEnabled
    }

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return actions
            .filter { action in
                action.title.localizedCaseInsensitiveContains(q) ||
                action.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
            }
            .prefix(Self.maxResultsCount)
            .map { [windowManager] action in
                PaletteCommand(
                    id: UUID(),
                    title: action.title,
                    subtitle: nil,
                    icon: .sfSymbol("rectangle.inset.filled"),
                    keywords: action.keywords,
                    action: .execute { _ = windowManager.perform(action) },
                    category: "Window"
                )
            }
    }
}
```

- [x] **Step 4: Update command palette state**

In `platforms/macos/Atlas/AtlasApp.swift`, add this stored property to `CommandPaletteState`:

```swift
private let windowManager: WindowManaging
private var isWindowManagementEnabled = false
```

Update the `CommandPaletteState` initializer signature from:

```swift
init() {
```

to:

```swift
init(windowManager: WindowManaging = AccessibilityWindowManager()) {
    self.windowManager = windowManager
```

Replace the provider initialization:

```swift
let windowManagementProvider = WindowManagementProvider()
```

with:

```swift
let windowManagementProvider = WindowManagementProvider(
    windowManager: windowManager,
    isEnabled: { [weak self] in self?.isWindowManagementEnabled == true }
)
```

Add this method to `CommandPaletteState`:

```swift
func setWindowManagementEnabled(_ enabled: Bool) {
    isWindowManagementEnabled = enabled
}
```

- [x] **Step 5: Run provider tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WindowManagementProviderTests
```

Expected: PASS.

---

### Task 5: Window Grid Panel

**Files:**
- Create: `platforms/macos/Atlas/WindowGridPanel.swift`
- Create: `platforms/macos/AtlasTests/WindowGridPanelTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Create panel tests with injected state**

Create `platforms/macos/AtlasTests/WindowGridPanelTests.swift`:

```swift
import XCTest
@testable import Atlas

@MainActor
final class WindowGridPanelTests: XCTestCase {
    func testGridPositionsAreStableTopToBottomLeftToRight() {
        XCTAssertEqual(WindowGridPanel.gridPositions, [
            WindowGridPosition(row: 0, column: 0),
            WindowGridPosition(row: 0, column: 1),
            WindowGridPosition(row: 0, column: 2),
            WindowGridPosition(row: 1, column: 0),
            WindowGridPosition(row: 1, column: 1),
            WindowGridPosition(row: 1, column: 2),
            WindowGridPosition(row: 2, column: 0),
            WindowGridPosition(row: 2, column: 1),
            WindowGridPosition(row: 2, column: 2),
        ])
    }

    func testSelectingGridCellPerformsGridActionWhenEnabledAndTrusted() {
        let manager = FakeWindowGridManager()
        let permission = FakeWindowManagementPermissionChecker(isTrusted: true)
        let model = WindowGridPanelModel(
            windowManager: manager,
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        let result = model.select(position: WindowGridPosition(row: 2, column: 1))

        XCTAssertEqual(result, .performed)
        XCTAssertEqual(manager.performedActions, [.grid(WindowGridPosition(row: 2, column: 1))])
        XCTAssertEqual(permission.requestCount, 0)
    }

    func testSelectingGridCellDoesNothingWhenFeatureDisabled() {
        let manager = FakeWindowGridManager()
        let permission = FakeWindowManagementPermissionChecker(isTrusted: true)
        let model = WindowGridPanelModel(
            windowManager: manager,
            permissionChecker: permission,
            isFeatureEnabled: { false }
        )

        let result = model.select(position: WindowGridPosition(row: 0, column: 0))

        XCTAssertEqual(result, .featureDisabled)
        XCTAssertTrue(manager.performedActions.isEmpty)
    }

    func testSelectingGridCellRequestsAccessibilityWhenNotTrusted() {
        let manager = FakeWindowGridManager()
        let permission = FakeWindowManagementPermissionChecker(isTrusted: false)
        let model = WindowGridPanelModel(
            windowManager: manager,
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        let result = model.select(position: WindowGridPosition(row: 1, column: 1))

        XCTAssertEqual(result, .permissionRequired)
        XCTAssertTrue(manager.performedActions.isEmpty)
        XCTAssertEqual(permission.requestCount, 1)
    }
}

private final class FakeWindowGridManager: WindowManaging {
    private(set) var performedActions: [WindowManagementAction] = []

    @discardableResult
    func perform(_ action: WindowManagementAction) -> Bool {
        performedActions.append(action)
        return true
    }
}

private final class FakeWindowManagementPermissionChecker: WindowManagementPermissionChecking {
    var isTrusted: Bool
    private(set) var requestCount = 0

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func requestPermission() {
        requestCount += 1
    }
}
```

- [x] **Step 2: Run panel tests and verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WindowGridPanelTests
```

Expected: FAIL because `WindowGridPanelModel` and `WindowGridPanel` do not exist yet.

- [x] **Step 3: Create the panel**

Create `platforms/macos/Atlas/WindowGridPanel.swift`:

```swift
import SwiftUI

enum WindowGridSelectionResult: Equatable {
    case performed
    case failed
    case featureDisabled
    case permissionRequired
}

@MainActor
final class WindowGridPanelModel: ObservableObject {
    private let windowManager: WindowManaging
    private let permissionChecker: WindowManagementPermissionChecking
    private let isFeatureEnabled: () -> Bool

    init(
        windowManager: WindowManaging,
        permissionChecker: WindowManagementPermissionChecking,
        isFeatureEnabled: @escaping () -> Bool
    ) {
        self.windowManager = windowManager
        self.permissionChecker = permissionChecker
        self.isFeatureEnabled = isFeatureEnabled
    }

    var accessibilityStatusText: String {
        permissionChecker.isTrusted ? "Accessibility access enabled" : "Accessibility access required"
    }

    func requestPermission() {
        permissionChecker.requestPermission()
    }

    @discardableResult
    func select(position: WindowGridPosition) -> WindowGridSelectionResult {
        guard isFeatureEnabled() else { return .featureDisabled }

        guard permissionChecker.isTrusted else {
            permissionChecker.requestPermission()
            return .permissionRequired
        }

        return windowManager.perform(.grid(position)) ? .performed : .failed
    }
}

struct WindowGridPanel: View {
    static let gridPositions: [WindowGridPosition] = [
        WindowGridPosition(row: 0, column: 0),
        WindowGridPosition(row: 0, column: 1),
        WindowGridPosition(row: 0, column: 2),
        WindowGridPosition(row: 1, column: 0),
        WindowGridPosition(row: 1, column: 1),
        WindowGridPosition(row: 1, column: 2),
        WindowGridPosition(row: 2, column: 0),
        WindowGridPosition(row: 2, column: 1),
        WindowGridPosition(row: 2, column: 2),
    ]

    @ObservedObject var model: WindowGridPanelModel
    let onResult: (WindowGridSelectionResult) -> Void

    private let columns = Array(repeating: GridItem(.fixed(42), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Window Grid").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Button("Access") {
                    model.requestPermission()
                }
                .disabled(model.accessibilityStatusText == "Accessibility access enabled")
            }

            Text(model.accessibilityStatusText)
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.gridPositions, id: \.self) { position in
                    Button {
                        onResult(model.select(position: position))
                    } label: {
                        Text(position.titleSuffix)
                            .font(.caption2)
                            .frame(width: 42, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Move frontmost window \(position.titleSuffix)")
                }
            }
        }
    }
}
```

- [x] **Step 4: Add new files to the Xcode project**

Run this exact script from the repository root:

```bash
ruby <<'RUBY'
require 'xcodeproj'

project_path = 'platforms/macos/Atlas.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |target| target.name == 'Atlas' }
test_target = project.targets.find { |target| target.name == 'AtlasTests' }
atlas_group = project.main_group['Atlas']
tests_group = project.main_group['AtlasTests']

abort('Atlas target not found') unless app_target
abort('AtlasTests target not found') unless test_target
abort('Atlas group not found') unless atlas_group
abort('AtlasTests group not found') unless tests_group

[
  [atlas_group, app_target, 'WindowGridPanel.swift'],
  [atlas_group, app_target, 'WindowManagementPermissions.swift'],
  [tests_group, test_target, 'WindowGridPanelTests.swift'],
].each do |group, target, path|
  file_ref = group.files.find { |file| file.path == path } || group.new_file(path)
  unless target.source_build_phase.files_references.include?(file_ref)
    target.add_file_references([file_ref])
  end
end

project.save
RUBY
```

- [x] **Step 5: Run panel tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WindowGridPanelTests
```

Expected: PASS.

---

### Task 6: Show the Panel Behind Feature Center Gating

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Test: `platforms/macos/AtlasTests/WindowGridPanelTests.swift`

- [x] **Step 1: Create shared window manager state in AtlasApp**

In `platforms/macos/Atlas/AtlasApp.swift`, replace the current `AtlasApp` stored property and `ContentView` construction with:

```swift
@main
struct AtlasApp: App {
    @StateObject private var paletteState: CommandPaletteState
    private let windowManager: AccessibilityWindowManager
    private let windowPermissionChecker = AccessibilityPermissionChecker()

    init() {
        let sharedWindowManager = AccessibilityWindowManager()
        self.windowManager = sharedWindowManager
        _paletteState = StateObject(
            wrappedValue: CommandPaletteState(windowManager: sharedWindowManager)
        )
    }

    var body: some Scene {
        MenuBarExtra("Atlas", systemImage: "square.stack.3d.up.fill") {
            ContentView(
                windowManager: windowManager,
                windowPermissionChecker: windowPermissionChecker,
                paletteState: paletteState
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            AtlasSettingsView(paletteController: paletteState.controller)
        }
    }
}
```

- [x] **Step 2: Accept shared dependencies in ContentView**

In `platforms/macos/Atlas/ContentView.swift`, add these stored properties near `var paletteState`:

```swift
let windowManager: WindowManaging
let windowPermissionChecker: WindowManagementPermissionChecking
var paletteState: CommandPaletteState? = nil
```

Remove the old standalone `var paletteState: CommandPaletteState? = nil` line so `ContentView` has only one `paletteState` property.

- [x] **Step 3: Show the panel only when the feature is enabled**

In `ContentView.body`, insert this block after the monitoring panel divider and before `FeatureCenterPanel`:

```swift
if isFeatureEnabled(.windowManager) {
    WindowGridPanel(
        model: WindowGridPanelModel(
            windowManager: windowManager,
            permissionChecker: windowPermissionChecker,
            isFeatureEnabled: { isFeatureEnabled(.windowManager) }
        ),
        onResult: handleWindowGridResult
    )

    Divider()
}
```

Add this method to `ContentView`:

```swift
private func handleWindowGridResult(_ result: WindowGridSelectionResult) {
    switch result {
    case .performed:
        showStatus("Moved frontmost window")
    case .failed:
        showStatus("No active window to move", kind: .error)
    case .featureDisabled:
        showStatus("Window Manager is disabled", kind: .error)
    case .permissionRequired:
        showStatus("Accessibility permission is required", kind: .error)
    }
}
```

- [x] **Step 4: Sync Feature Center state into command palette gating**

In `ContentView.startModules()`, after `enabledFeatures = FeatureStateReducer.enabledMap(from: loadedFeatures)`, add:

```swift
paletteState?.setWindowManagementEnabled(isFeatureEnabled(.windowManager))
```

In `ContentView.refreshFeature(_:enabled:)`, add this block before the monitoring guard:

```swift
if feature == AtlasModule.windowManager.featureName {
    paletteState?.setWindowManagementEnabled(enabled)
    return
}
```

- [x] **Step 5: Run focused window tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WindowManagementServiceTests -only-testing:AtlasTests/WindowManagementProviderTests -only-testing:AtlasTests/WindowGridPanelTests -only-testing:AtlasTests/FeatureModelsTests
```

Expected: PASS.

---

### Task 7: Final Verification and Commit

**Files:**
- Verify: `platforms/macos/Atlas/WindowManagementService.swift`
- Verify: `platforms/macos/Atlas/WindowGridPanel.swift`
- Verify: `platforms/macos/Atlas/WindowManagementPermissions.swift`
- Verify: `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift`
- Verify: `platforms/macos/Atlas/ContentView.swift`
- Verify: `platforms/macos/Atlas/AtlasApp.swift`
- Verify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Run the focused test suite**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WindowManagementServiceTests -only-testing:AtlasTests/WindowManagementProviderTests -only-testing:AtlasTests/WindowGridPanelTests -only-testing:AtlasTests/FeatureModelsTests
```

Expected: PASS.

- [x] **Step 2: Run the broader macOS XCTest suite**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: PASS. Non-blocking CoreSimulator warnings are acceptable when the macOS tests still finish with `** TEST SUCCEEDED **`.

- [x] **Step 3: Review changed files**

Run:

```bash
git diff -- platforms/macos/Atlas/WindowManagementService.swift platforms/macos/Atlas/WindowGridPanel.swift platforms/macos/Atlas/WindowManagementPermissions.swift platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift platforms/macos/Atlas/AtlasModule.swift platforms/macos/Atlas/FeatureModels.swift platforms/macos/Atlas/ContentView.swift platforms/macos/Atlas/AtlasApp.swift platforms/macos/AtlasTests/WindowManagementServiceTests.swift platforms/macos/AtlasTests/WindowManagementProviderTests.swift platforms/macos/AtlasTests/WindowGridPanelTests.swift platforms/macos/AtlasTests/FeatureModelsTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: Diff contains only window grid, feature gating, permission, tests, and PBX membership changes.

- [x] **Step 4: Commit**

Run:

```bash
git add platforms/macos/Atlas/WindowManagementService.swift platforms/macos/Atlas/WindowGridPanel.swift platforms/macos/Atlas/WindowManagementPermissions.swift platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift platforms/macos/Atlas/AtlasModule.swift platforms/macos/Atlas/FeatureModels.swift platforms/macos/Atlas/ContentView.swift platforms/macos/Atlas/AtlasApp.swift platforms/macos/AtlasTests/WindowManagementServiceTests.swift platforms/macos/AtlasTests/WindowManagementProviderTests.swift platforms/macos/AtlasTests/WindowGridPanelTests.swift platforms/macos/AtlasTests/FeatureModelsTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: add window grid"
```

Expected: Commit includes the grid panel, permission handling, Feature Center gating, injected-state tests, and explicit Xcode project membership updates.

## Self-Review

- Spec coverage: 3x3 grid UI is Task 5 and Task 6; active window targeting is Task 2 using `AccessibilityWindowManager`; Accessibility permission handling is Task 3 and Task 5; multi-display mapping is Task 2; Feature Center gating is Task 1, Task 4, and Task 6; injected window manager state tests are Task 5.
- Red-flag scan: no banned planning shortcuts are present.
- Type consistency: `WindowGridPosition`, `WindowManagementAction.grid`, `WindowGridPanelModel`, and `WindowManagementPermissionChecking` are defined before later tasks use them.
