# Workspaces v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add named workspace capture and restore for current visible window layouts.

**Architecture:** Keep workspace capture and restore in Swift because it depends on AppKit Accessibility and app activation. Represent workspaces as Codable value types in a local JSON store, use injected snapshot/restorer and permission protocols in tests, and gate UI plus command palette actions behind the existing `window-manager` Feature Center flag.

**Tech Stack:** Swift, SwiftUI, Foundation JSON persistence, AppKit Accessibility APIs, XCTest, explicit Xcode PBX project membership via `xcodeproj`.

---

## Scope

This plan implements:

- Capture current layout from visible windows.
- Save a named workspace locally.
- Restore a saved workspace by matching app bundle identifier and window title.
- Report missing apps and missing windows without failing the whole restore.
- Command palette actions for opening the workspace panel, saving the current layout, and restoring saved workspaces.
- Feature Center gating through `window-manager`.
- Tests with injected window snapshots and injected restore behavior.

Out of scope:

- Cross-device sync.
- Launching missing apps automatically.
- Matching browser tabs or document URLs.
- Timed automatic workspace capture.
- Workspace thumbnails.

## Current Baseline

Window management currently supports fixed actions for the frontmost window through:

- `platforms/macos/Atlas/WindowManagementService.swift`
- `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift`
- `platforms/macos/AtlasTests/WindowManagementServiceTests.swift`
- `platforms/macos/AtlasTests/WindowManagementProviderTests.swift`

This plan depends on the window grid plan having added `AtlasModule.windowManager`, `CommandPaletteState.setWindowManagementEnabled(_:)`, and `WindowManagementPermissionChecking`. If the grid plan has not run, implement Task 1 and Task 3 from `docs/superpowers/plans/2026-05-22-window-grid-v1.md` first.

## File Map

**New files:**

- `platforms/macos/Atlas/WorkspaceModels.swift`
  - Defines `Workspace`, `WorkspaceWindow`, `WorkspaceRestoreReport`, and `WorkspaceRestoreIssue`.

- `platforms/macos/Atlas/WorkspaceStore.swift`
  - Defines `WorkspaceStoring` and `WorkspaceStore`.
  - Persists workspaces as JSON under Application Support.

- `platforms/macos/Atlas/WorkspaceWindowService.swift`
  - Defines `WindowSnapshotProviding` and `WorkspaceRestoring`.
  - Provides live Accessibility implementation for capture and restore.

- `platforms/macos/Atlas/WorkspacePanel.swift`
  - SwiftUI panel to enter a workspace name, save current layout, restore saved workspaces, and show restore issues.
  - Injects `WindowManagementPermissionChecking` and reports permission-denied status before capture or restore.

- `platforms/macos/Atlas/CommandPalette/WorkspaceProvider.swift`
  - Command palette provider for workspace actions and saved workspace restore commands.

- `platforms/macos/AtlasTests/WorkspaceModelsTests.swift`
  - Tests Codable and restore issue values.

- `platforms/macos/AtlasTests/WorkspaceStoreTests.swift`
  - Tests save, load, delete, and replacement behavior using a temp file URL.

- `platforms/macos/AtlasTests/WorkspaceWindowServiceTests.swift`
  - Tests capture and restore orchestration with injected snapshots.

- `platforms/macos/AtlasTests/WorkspaceProviderTests.swift`
  - Tests command palette gating, save action dispatch, panel action dispatch, and saved workspace restore actions.

- `platforms/macos/AtlasTests/WorkspacePanelTests.swift`
  - Tests panel model behavior with injected store, snapshot/restorer, and permission state.

**Modified files:**

- `platforms/macos/Atlas/ContentView.swift`
  - Shows `WorkspacePanel` only when `window-manager` is enabled.
  - Installs command palette workspace view builder.

- `platforms/macos/Atlas/AtlasApp.swift`
  - Creates `WorkspaceStore`, `AccessibilityWorkspaceWindowService`, and `WorkspaceProvider`.
  - Gates provider results through `CommandPaletteState`.

- `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`
  - Passes an optional workspace panel view builder into `CommandPaletteView`.

- `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`
  - Adds `PaletteDestination.workspaces`.

- `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`
  - Adds `workspaceViewBuilder` and handles `.workspaces` in `subView(for:)` using the existing `PaletteAction.push(PaletteDestination)` navigation path.

- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new Swift app files to the `Atlas` target sources.
  - Adds new Swift test files to the `AtlasTests` target sources.

---

### Task 1: Workspace Value Types

**Files:**
- Create: `platforms/macos/Atlas/WorkspaceModels.swift`
- Create: `platforms/macos/AtlasTests/WorkspaceModelsTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing model tests**

Create `platforms/macos/AtlasTests/WorkspaceModelsTests.swift`:

```swift
import XCTest
@testable import Atlas

final class WorkspaceModelsTests: XCTestCase {
    func testWorkspaceRoundTripsThroughJSON() throws {
        let workspace = Workspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Writing",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            windows: [
                WorkspaceWindow(
                    bundleIdentifier: "com.apple.TextEdit",
                    appName: "TextEdit",
                    windowTitle: "Draft.txt",
                    frame: CGRect(x: 10, y: 20, width: 800, height: 600),
                    screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
                ),
            ]
        )

        let data = try JSONEncoder.workspaceEncoder.encode([workspace])
        let decoded = try JSONDecoder.workspaceDecoder.decode([Workspace].self, from: data)

        XCTAssertEqual(decoded, [workspace])
    }

    func testRestoreReportSeparatesRestoredAndMissingWindows() {
        let restored = WorkspaceWindow(
            bundleIdentifier: "com.apple.Terminal",
            appName: "Terminal",
            windowTitle: "atlas",
            frame: CGRect(x: 0, y: 0, width: 700, height: 500),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        let issue = WorkspaceRestoreIssue(
            window: restored,
            reason: .windowNotFound
        )

        let report = WorkspaceRestoreReport(restoredWindows: [restored], issues: [issue])

        XCTAssertEqual(report.restoredWindows, [restored])
        XCTAssertEqual(report.issues, [issue])
        XCTAssertEqual(issue.message, "Terminal - atlas: window not found")
    }
}
```

- [ ] **Step 2: Run model tests and verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspaceModelsTests
```

Expected: FAIL because workspace model types do not exist yet.

- [ ] **Step 3: Create workspace models**

Create `platforms/macos/Atlas/WorkspaceModels.swift`:

```swift
import CoreGraphics
import Foundation

struct Workspace: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var windows: [WorkspaceWindow]
}

struct WorkspaceWindow: Codable, Equatable, Identifiable {
    var id: String {
        "\(bundleIdentifier)|\(appName)|\(windowTitle)"
    }

    let bundleIdentifier: String
    let appName: String
    let windowTitle: String
    let frame: CGRect
    let screenFrame: CGRect
}

struct WorkspaceRestoreReport: Equatable {
    var restoredWindows: [WorkspaceWindow]
    var issues: [WorkspaceRestoreIssue]
}

struct WorkspaceRestoreIssue: Equatable, Identifiable {
    enum Reason: String, Equatable {
        case appNotRunning
        case windowNotFound
        case permissionDenied
        case moveFailed
    }

    var id: String {
        "\(window.id)|\(reason.rawValue)"
    }

    let window: WorkspaceWindow
    let reason: Reason

    var message: String {
        "\(window.appName) - \(window.windowTitle): \(reason.message)"
    }
}

private extension WorkspaceRestoreIssue.Reason {
    var message: String {
        switch self {
        case .appNotRunning:
            return "app not running"
        case .windowNotFound:
            return "window not found"
        case .permissionDenied:
            return "Accessibility permission denied"
        case .moveFailed:
            return "window move failed"
        }
    }
}

extension JSONEncoder {
    static var workspaceEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var workspaceDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 4: Add model files to the Xcode project**

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
  [atlas_group, app_target, 'WorkspaceModels.swift'],
  [tests_group, test_target, 'WorkspaceModelsTests.swift'],
].each do |group, target, path|
  file_ref = group.files.find { |file| file.path == path } || group.new_file(path)
  target.add_file_references([file_ref]) unless target.source_build_phase.files_references.include?(file_ref)
end

project.save
RUBY
```

- [ ] **Step 5: Run model tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspaceModelsTests
```

Expected: PASS.

---

### Task 2: Workspace Store

**Files:**
- Create: `platforms/macos/Atlas/WorkspaceStore.swift`
- Create: `platforms/macos/AtlasTests/WorkspaceStoreTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing store tests**

Create `platforms/macos/AtlasTests/WorkspaceStoreTests.swift`:

```swift
import XCTest
@testable import Atlas

final class WorkspaceStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("workspaces.json")
    }

    func testSaveAndLoadWorkspace() throws {
        let store = WorkspaceStore(fileURL: fileURL)
        let workspace = makeWorkspace(id: "00000000-0000-0000-0000-000000000001", name: "Dev")

        try store.save(workspace)

        XCTAssertEqual(try store.load(), [workspace])
    }

    func testSavingSameIDReplacesExistingWorkspaceAndSortsByUpdatedAtDescending() throws {
        let store = WorkspaceStore(fileURL: fileURL)
        let first = makeWorkspace(id: "00000000-0000-0000-0000-000000000001", name: "First", updatedAt: 10)
        let replacement = makeWorkspace(id: "00000000-0000-0000-0000-000000000001", name: "Replacement", updatedAt: 30)
        let second = makeWorkspace(id: "00000000-0000-0000-0000-000000000002", name: "Second", updatedAt: 20)

        try store.save(first)
        try store.save(second)
        try store.save(replacement)

        XCTAssertEqual(try store.load().map(\.name), ["Replacement", "Second"])
    }

    func testDeleteWorkspaceRemovesMatchingID() throws {
        let store = WorkspaceStore(fileURL: fileURL)
        let first = makeWorkspace(id: "00000000-0000-0000-0000-000000000001", name: "First")
        let second = makeWorkspace(id: "00000000-0000-0000-0000-000000000002", name: "Second")
        try store.save(first)
        try store.save(second)

        try store.delete(id: first.id)

        XCTAssertEqual(try store.load(), [second])
    }

    private func makeWorkspace(
        id: String,
        name: String,
        updatedAt: TimeInterval = 20
    ) -> Workspace {
        Workspace(
            id: UUID(uuidString: id)!,
            name: name,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            windows: []
        )
    }
}
```

- [ ] **Step 2: Run store tests and verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspaceStoreTests
```

Expected: FAIL because `WorkspaceStore` does not exist yet.

- [ ] **Step 3: Create the store**

Create `platforms/macos/Atlas/WorkspaceStore.swift`:

```swift
import Foundation

protocol WorkspaceStoring {
    func load() throws -> [Workspace]
    func save(_ workspace: Workspace) throws
    func delete(id: UUID) throws
}

final class WorkspaceStore: WorkspaceStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = WorkspaceStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [Workspace] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.workspaceDecoder
            .decode([Workspace].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ workspace: Workspace) throws {
        var workspaces = try load().filter { $0.id != workspace.id }
        workspaces.append(workspace)
        try write(workspaces.sorted { $0.updatedAt > $1.updatedAt })
    }

    func delete(id: UUID) throws {
        try write(try load().filter { $0.id != id })
    }

    private func write(_ workspaces: [Workspace]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.workspaceEncoder.encode(workspaces)
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("workspaces.json")
    }
}
```

- [ ] **Step 4: Add store files to the Xcode project**

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
  [atlas_group, app_target, 'WorkspaceStore.swift'],
  [tests_group, test_target, 'WorkspaceStoreTests.swift'],
].each do |group, target, path|
  file_ref = group.files.find { |file| file.path == path } || group.new_file(path)
  target.add_file_references([file_ref]) unless target.source_build_phase.files_references.include?(file_ref)
end

project.save
RUBY
```

- [ ] **Step 5: Run store tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspaceStoreTests
```

Expected: PASS.

---

### Task 3: Capture and Restore Window Layouts

**Files:**
- Create: `platforms/macos/Atlas/WorkspaceWindowService.swift`
- Create: `platforms/macos/AtlasTests/WorkspaceWindowServiceTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing injected snapshot tests**

Create `platforms/macos/AtlasTests/WorkspaceWindowServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class WorkspaceWindowServiceTests: XCTestCase {
    func testCaptureCreatesNamedWorkspaceFromInjectedSnapshots() throws {
        let service = WorkspaceWindowService(
            snapshotProvider: FakeSnapshotProvider(windows: [window(title: "Editor")]),
            restorer: FakeWorkspaceRestorer()
        )

        let workspace = try service.captureWorkspace(named: "Coding", now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(workspace.name, "Coding")
        XCTAssertEqual(workspace.createdAt, Date(timeIntervalSince1970: 50))
        XCTAssertEqual(workspace.updatedAt, Date(timeIntervalSince1970: 50))
        XCTAssertEqual(workspace.windows.map(\.windowTitle), ["Editor"])
    }

    func testRestoreReturnsReportFromInjectedRestorer() throws {
        let target = window(title: "Editor")
        let expected = WorkspaceRestoreReport(
            restoredWindows: [target],
            issues: [WorkspaceRestoreIssue(window: window(title: "Missing"), reason: .windowNotFound)]
        )
        let restorer = FakeWorkspaceRestorer(report: expected)
        let service = WorkspaceWindowService(
            snapshotProvider: FakeSnapshotProvider(windows: []),
            restorer: restorer
        )
        let workspace = Workspace(
            id: UUID(),
            name: "Coding",
            createdAt: Date(),
            updatedAt: Date(),
            windows: [target]
        )

        let report = try service.restore(workspace)

        XCTAssertEqual(report, expected)
        XCTAssertEqual(restorer.restoredWorkspaces, [workspace])
    }
}

private func window(title: String) -> WorkspaceWindow {
    WorkspaceWindow(
        bundleIdentifier: "com.example.editor",
        appName: "Editor",
        windowTitle: title,
        frame: CGRect(x: 10, y: 20, width: 800, height: 600),
        screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
    )
}

private struct FakeSnapshotProvider: WindowSnapshotProviding {
    let windows: [WorkspaceWindow]

    func currentWindowSnapshots() throws -> [WorkspaceWindow] {
        windows
    }
}

private final class FakeWorkspaceRestorer: WorkspaceRestoring {
    let report: WorkspaceRestoreReport
    private(set) var restoredWorkspaces: [Workspace] = []

    init(report: WorkspaceRestoreReport = WorkspaceRestoreReport(restoredWindows: [], issues: [])) {
        self.report = report
    }

    func restore(_ workspace: Workspace) throws -> WorkspaceRestoreReport {
        restoredWorkspaces.append(workspace)
        return report
    }
}
```

- [ ] **Step 2: Run service tests and verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspaceWindowServiceTests
```

Expected: FAIL because workspace service protocols and types do not exist yet.

- [ ] **Step 3: Create the service boundary**

Create `platforms/macos/Atlas/WorkspaceWindowService.swift`:

```swift
import AppKit
import ApplicationServices
import Foundation

protocol WindowSnapshotProviding {
    func currentWindowSnapshots() throws -> [WorkspaceWindow]
}

protocol WorkspaceRestoring {
    func restore(_ workspace: Workspace) throws -> WorkspaceRestoreReport
}

final class WorkspaceWindowService {
    private let snapshotProvider: WindowSnapshotProviding
    private let restorer: WorkspaceRestoring

    init(
        snapshotProvider: WindowSnapshotProviding = AccessibilityWorkspaceWindowService(),
        restorer: WorkspaceRestoring = AccessibilityWorkspaceWindowService()
    ) {
        self.snapshotProvider = snapshotProvider
        self.restorer = restorer
    }

    func captureWorkspace(named name: String, now: Date = Date()) throws -> Workspace {
        Workspace(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            updatedAt: now,
            windows: try snapshotProvider.currentWindowSnapshots()
        )
    }

    func restore(_ workspace: Workspace) throws -> WorkspaceRestoreReport {
        try restorer.restore(workspace)
    }
}

final class AccessibilityWorkspaceWindowService: WindowSnapshotProviding, WorkspaceRestoring {
    func currentWindowSnapshots() throws -> [WorkspaceWindow] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            .map { $0 as NSArray }
            .map { $0.compactMap(snapshot(from:)) }
            ?? []
    }

    func restore(_ workspace: Workspace) throws -> WorkspaceRestoreReport {
        guard AXIsProcessTrusted() else {
            return WorkspaceRestoreReport(
                restoredWindows: [],
                issues: workspace.windows.map { WorkspaceRestoreIssue(window: $0, reason: .permissionDenied) }
            )
        }

        let runningApps = NSWorkspace.shared.runningApplications
        var restored: [WorkspaceWindow] = []
        var issues: [WorkspaceRestoreIssue] = []

        for target in workspace.windows {
            guard let app = runningApps.first(where: { $0.bundleIdentifier == target.bundleIdentifier }) else {
                issues.append(WorkspaceRestoreIssue(window: target, reason: .appNotRunning))
                continue
            }

            guard let window = focusedOrNamedWindow(for: app.processIdentifier, title: target.windowTitle) else {
                issues.append(WorkspaceRestoreIssue(window: target, reason: .windowNotFound))
                continue
            }

            if setFrame(target.frame, for: window) {
                restored.append(target)
            } else {
                issues.append(WorkspaceRestoreIssue(window: target, reason: .moveFailed))
            }
        }

        return WorkspaceRestoreReport(restoredWindows: restored, issues: issues)
    }

    private func snapshot(from raw: Any) -> WorkspaceWindow? {
        guard
            let dictionary = raw as? [String: Any],
            let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
            let title = dictionary[kCGWindowName as String] as? String,
            !title.isEmpty,
            let pid = dictionary[kCGWindowOwnerPID as String] as? pid_t,
            let bounds = dictionary[kCGWindowBounds as String] as? [String: Any],
            let x = bounds["X"] as? CGFloat,
            let y = bounds["Y"] as? CGFloat,
            let width = bounds["Width"] as? CGFloat,
            let height = bounds["Height"] as? CGFloat,
            width > 0,
            height > 0
        else {
            return nil
        }

        let app = NSRunningApplication(processIdentifier: pid)
        guard let bundleIdentifier = app?.bundleIdentifier else { return nil }
        let frame = CGRect(x: x, y: y, width: width, height: height)
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main

        return WorkspaceWindow(
            bundleIdentifier: bundleIdentifier,
            appName: ownerName,
            windowTitle: title,
            frame: frame,
            screenFrame: screen?.frame ?? .zero
        )
    }

    private func focusedOrNamedWindow(for pid: pid_t, title: String) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement]
        else {
            return nil
        }

        return windows.first { window in
            var rawTitle: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &rawTitle) == .success else {
                return false
            }
            return (rawTitle as? String) == title
        }
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

        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) == .success
            && AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success
    }
}
```

- [ ] **Step 4: Add service files to the Xcode project**

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
  [atlas_group, app_target, 'WorkspaceWindowService.swift'],
  [tests_group, test_target, 'WorkspaceWindowServiceTests.swift'],
].each do |group, target, path|
  file_ref = group.files.find { |file| file.path == path } || group.new_file(path)
  target.add_file_references([file_ref]) unless target.source_build_phase.files_references.include?(file_ref)
end

project.save
RUBY
```

- [ ] **Step 5: Run service tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspaceWindowServiceTests
```

Expected: PASS.

---

### Task 4: Workspace Panel Model and View

**Files:**
- Create: `platforms/macos/Atlas/WorkspacePanel.swift`
- Create: `platforms/macos/AtlasTests/WorkspacePanelTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing panel model tests**

Create `platforms/macos/AtlasTests/WorkspacePanelTests.swift`:

```swift
import XCTest
@testable import Atlas

@MainActor
final class WorkspacePanelTests: XCTestCase {
    func testSaveCurrentLayoutStoresCapturedWorkspace() throws {
        let store = FakeWorkspaceStore()
        let service = WorkspaceWindowService(
            snapshotProvider: FakeWorkspaceSnapshots(windows: [workspaceWindow("Editor")]),
            restorer: FakeWorkspaceRestore()
        )
        let permission = FakeWorkspacePermissionChecker(isTrusted: true)
        let model = WorkspacePanelModel(
            store: store,
            service: service,
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        try model.saveCurrentLayout(named: "Coding")

        XCTAssertEqual(store.savedWorkspaces.map(\.name), ["Coding"])
        XCTAssertEqual(model.workspaces.map(\.name), ["Coding"])
    }

    func testSaveCurrentLayoutDoesNotCaptureWhenFeatureDisabled() throws {
        let store = FakeWorkspaceStore()
        let service = WorkspaceWindowService(
            snapshotProvider: FakeWorkspaceSnapshots(windows: [workspaceWindow("Editor")]),
            restorer: FakeWorkspaceRestore()
        )
        let permission = FakeWorkspacePermissionChecker(isTrusted: true)
        let model = WorkspacePanelModel(
            store: store,
            service: service,
            permissionChecker: permission,
            isFeatureEnabled: { false }
        )

        try model.saveCurrentLayout(named: "Coding")

        XCTAssertTrue(store.savedWorkspaces.isEmpty)
        XCTAssertEqual(model.statusMessage, "Window Manager is disabled")
    }

    func testSaveCurrentLayoutRequestsPermissionWhenAccessibilityIsNotTrusted() throws {
        let store = FakeWorkspaceStore()
        let service = WorkspaceWindowService(
            snapshotProvider: FakeWorkspaceSnapshots(windows: [workspaceWindow("Editor")]),
            restorer: FakeWorkspaceRestore()
        )
        let permission = FakeWorkspacePermissionChecker(isTrusted: false)
        let model = WorkspacePanelModel(
            store: store,
            service: service,
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        try model.saveCurrentLayout(named: "Coding")

        XCTAssertTrue(store.savedWorkspaces.isEmpty)
        XCTAssertEqual(permission.requestCount, 1)
        XCTAssertEqual(model.statusMessage, "Accessibility permission is required")
    }

    func testRestoreRecordsMissingWindowMessage() throws {
        let store = FakeWorkspaceStore()
        let missing = workspaceWindow("Missing")
        let workspace = Workspace(id: UUID(), name: "Coding", createdAt: Date(), updatedAt: Date(), windows: [missing])
        store.workspaces = [workspace]
        let restore = FakeWorkspaceRestore(report: WorkspaceRestoreReport(
            restoredWindows: [],
            issues: [WorkspaceRestoreIssue(window: missing, reason: .windowNotFound)]
        ))
        let service = WorkspaceWindowService(
            snapshotProvider: FakeWorkspaceSnapshots(windows: []),
            restorer: restore
        )
        let permission = FakeWorkspacePermissionChecker(isTrusted: true)
        let model = WorkspacePanelModel(
            store: store,
            service: service,
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )
        try model.reload()

        try model.restore(workspace)

        XCTAssertEqual(model.restoreIssues.map(\.message), ["App - Missing: window not found"])
        XCTAssertEqual(model.statusMessage, "Restored 0 windows, 1 issue")
    }

    func testRestoreRequestsPermissionWhenAccessibilityIsNotTrusted() throws {
        let store = FakeWorkspaceStore()
        let workspace = Workspace(id: UUID(), name: "Coding", createdAt: Date(), updatedAt: Date(), windows: [])
        store.workspaces = [workspace]
        let permission = FakeWorkspacePermissionChecker(isTrusted: false)
        let model = WorkspacePanelModel(
            store: store,
            service: WorkspaceWindowService(
                snapshotProvider: FakeWorkspaceSnapshots(windows: []),
                restorer: FakeWorkspaceRestore()
            ),
            permissionChecker: permission,
            isFeatureEnabled: { true }
        )

        try model.restore(workspace)

        XCTAssertEqual(permission.requestCount, 1)
        XCTAssertEqual(model.statusMessage, "Accessibility permission is required")
    }
}

private func workspaceWindow(_ title: String) -> WorkspaceWindow {
    WorkspaceWindow(
        bundleIdentifier: "com.example.app",
        appName: "App",
        windowTitle: title,
        frame: CGRect(x: 0, y: 0, width: 500, height: 400),
        screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
    )
}

private final class FakeWorkspaceStore: WorkspaceStoring {
    var workspaces: [Workspace] = []
    private(set) var savedWorkspaces: [Workspace] = []

    func load() throws -> [Workspace] {
        workspaces
    }

    func save(_ workspace: Workspace) throws {
        savedWorkspaces.append(workspace)
        workspaces = workspaces.filter { $0.id != workspace.id } + [workspace]
    }

    func delete(id: UUID) throws {
        workspaces.removeAll { $0.id == id }
    }
}

private struct FakeWorkspaceSnapshots: WindowSnapshotProviding {
    let windows: [WorkspaceWindow]

    func currentWindowSnapshots() throws -> [WorkspaceWindow] {
        windows
    }
}

private final class FakeWorkspaceRestore: WorkspaceRestoring {
    let report: WorkspaceRestoreReport

    init(report: WorkspaceRestoreReport = WorkspaceRestoreReport(restoredWindows: [], issues: [])) {
        self.report = report
    }

    func restore(_ workspace: Workspace) throws -> WorkspaceRestoreReport {
        report
    }
}

private final class FakeWorkspacePermissionChecker: WindowManagementPermissionChecking {
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

- [ ] **Step 2: Run panel tests and verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspacePanelTests
```

Expected: FAIL because `WorkspacePanelModel` does not exist yet.

- [ ] **Step 3: Create panel model and view**

Create `platforms/macos/Atlas/WorkspacePanel.swift`:

```swift
import SwiftUI

@MainActor
final class WorkspacePanelModel: ObservableObject {
    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var restoreIssues: [WorkspaceRestoreIssue] = []
    @Published private(set) var statusMessage: String = ""

    private let store: WorkspaceStoring
    private let service: WorkspaceWindowService
    private let permissionChecker: WindowManagementPermissionChecking
    private let isFeatureEnabled: () -> Bool

    init(
        store: WorkspaceStoring,
        service: WorkspaceWindowService,
        permissionChecker: WindowManagementPermissionChecking,
        isFeatureEnabled: @escaping () -> Bool
    ) {
        self.store = store
        self.service = service
        self.permissionChecker = permissionChecker
        self.isFeatureEnabled = isFeatureEnabled
    }

    func reload() throws {
        workspaces = try store.load()
    }

    func saveCurrentLayout(named name: String) throws {
        guard isFeatureEnabled() else {
            statusMessage = "Window Manager is disabled"
            return
        }

        guard permissionChecker.isTrusted else {
            permissionChecker.requestPermission()
            statusMessage = "Accessibility permission is required"
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "Workspace name is required"
            return
        }

        let workspace = try service.captureWorkspace(named: trimmedName)
        try store.save(workspace)
        try reload()
        statusMessage = "Saved \(workspace.windows.count) windows"
    }

    func restore(_ workspace: Workspace) throws {
        guard isFeatureEnabled() else {
            statusMessage = "Window Manager is disabled"
            return
        }

        guard permissionChecker.isTrusted else {
            permissionChecker.requestPermission()
            statusMessage = "Accessibility permission is required"
            return
        }

        let report = try service.restore(workspace)
        restoreIssues = report.issues
        statusMessage = "Restored \(report.restoredWindows.count) windows, \(report.issues.count) issue"
    }

    func delete(_ workspace: Workspace) throws {
        try store.delete(id: workspace.id)
        try reload()
        statusMessage = "Deleted \(workspace.name)"
    }
}

struct WorkspacePanel: View {
    @ObservedObject var model: WorkspacePanelModel
    @State private var workspaceName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workspaces").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Button("Save") {
                    try? model.saveCurrentLayout(named: workspaceName)
                    workspaceName = ""
                }
            }

            TextField("Workspace name", text: $workspaceName)

            ForEach(model.workspaces) { workspace in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                        Text("\(workspace.windows.count) windows")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Restore") {
                        try? model.restore(workspace)
                    }
                    Button("Delete") {
                        try? model.delete(workspace)
                    }
                }
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(model.restoreIssues) { issue in
                Text(issue.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            try? model.reload()
        }
    }
}
```

- [ ] **Step 4: Add panel files to the Xcode project**

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
  [atlas_group, app_target, 'WorkspacePanel.swift'],
  [tests_group, test_target, 'WorkspacePanelTests.swift'],
].each do |group, target, path|
  file_ref = group.files.find { |file| file.path == path } || group.new_file(path)
  target.add_file_references([file_ref]) unless target.source_build_phase.files_references.include?(file_ref)
end

project.save
RUBY
```

- [ ] **Step 5: Run panel tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspacePanelTests
```

Expected: PASS.

---

### Task 5: Command Palette Workspace Actions

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/WorkspaceProvider.swift`
- Modify: `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`
- Modify: `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`
- Modify: `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Create: `platforms/macos/AtlasTests/WorkspaceProviderTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing provider tests**

Create `platforms/macos/AtlasTests/WorkspaceProviderTests.swift`:

```swift
import XCTest
@testable import Atlas

final class WorkspaceProviderTests: XCTestCase {
    func testDisabledProviderReturnsNoResults() {
        let provider = WorkspaceProvider(store: FakeWorkspaceProviderStore(), isEnabled: { false })

        XCTAssertTrue(provider.results(for: "workspace").isEmpty)
    }

    func testWorkspaceQueryReturnsOpenAndSaveActions() {
        let provider = WorkspaceProvider(store: FakeWorkspaceProviderStore(), isEnabled: { true })

        let results = provider.results(for: "workspace")

        XCTAssertEqual(results.map(\.title), ["Open Workspaces", "Save Current Workspace"])
    }

    func testSavedWorkspaceAppearsAsRestoreAction() {
        let store = FakeWorkspaceProviderStore()
        store.workspaces = [workspace(name: "Writing")]
        let provider = WorkspaceProvider(store: store, isEnabled: { true })

        let results = provider.results(for: "writing")

        XCTAssertEqual(results.map(\.title), ["Restore Workspace: Writing"])
    }

    func testOpenActionDispatchesPanelCallback() {
        let provider = WorkspaceProvider(
            store: FakeWorkspaceProviderStore(),
            isEnabled: { true }
        )

        let command = provider.results(for: "open workspaces").first

        if case .push(.workspaces)? = command?.action {
            XCTAssertEqual(command?.title, "Open Workspaces")
        } else {
            XCTFail("expected Open Workspaces to push the workspaces destination")
        }
    }

    func testSaveActionDispatchesSaveCallback() {
        var saveCount = 0
        let provider = WorkspaceProvider(
            store: FakeWorkspaceProviderStore(),
            isEnabled: { true },
            onSaveCurrent: { saveCount += 1 }
        )

        execute(provider.results(for: "save current workspace").first)

        XCTAssertEqual(saveCount, 1)
    }

    func testRestoreActionDispatchesWorkspaceCallback() {
        let store = FakeWorkspaceProviderStore()
        let saved = workspace(name: "Writing")
        store.workspaces = [saved]
        var restored: [Workspace] = []
        let provider = WorkspaceProvider(
            store: store,
            isEnabled: { true },
            onRestore: { restored.append($0) }
        )

        execute(provider.results(for: "writing").first)

        XCTAssertEqual(restored, [saved])
    }

    private func execute(_ command: PaletteCommand?) {
        if case .execute(let action)? = command?.action {
            action()
        } else {
            XCTFail("expected execute action")
        }
    }
}

private final class FakeWorkspaceProviderStore: WorkspaceStoring {
    var workspaces: [Workspace] = []

    func load() throws -> [Workspace] {
        workspaces
    }

    func save(_ workspace: Workspace) throws {
        workspaces.append(workspace)
    }

    func delete(id: UUID) throws {
        workspaces.removeAll { $0.id == id }
    }
}

private func workspace(name: String) -> Workspace {
    Workspace(id: UUID(), name: name, createdAt: Date(), updatedAt: Date(), windows: [])
}
```

- [ ] **Step 2: Run provider tests and verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspaceProviderTests
```

Expected: FAIL because `WorkspaceProvider` does not exist yet.

- [ ] **Step 3: Create the provider**

Create `platforms/macos/Atlas/CommandPalette/WorkspaceProvider.swift`:

```swift
import Foundation

final class WorkspaceProvider: CommandProviding {
    private let store: WorkspaceStoring
    private let isEnabled: () -> Bool
    private let onSaveCurrent: () -> Void
    private let onRestore: (Workspace) -> Void

    init(
        store: WorkspaceStoring,
        isEnabled: @escaping () -> Bool,
        onSaveCurrent: @escaping () -> Void = {},
        onRestore: @escaping (Workspace) -> Void = { _ in }
    ) {
        self.store = store
        self.isEnabled = isEnabled
        self.onSaveCurrent = onSaveCurrent
        self.onRestore = onRestore
    }

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var commands = fixedCommands().filter { command in
            command.title.localizedCaseInsensitiveContains(q) ||
            command.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }

        let workspaceCommands = (try? store.load())?.filter { workspace in
            workspace.name.localizedCaseInsensitiveContains(q) || q.localizedCaseInsensitiveContains("workspace")
        }.map { workspace in
            PaletteCommand(
                id: UUID(),
                title: "Restore Workspace: \(workspace.name)",
                subtitle: "\(workspace.windows.count) windows",
                icon: .sfSymbol("macwindow.on.rectangle"),
                keywords: ["workspace", "restore", workspace.name],
                action: .execute { [onRestore] in onRestore(workspace) },
                category: "Workspace"
            )
        } ?? []

        commands.append(contentsOf: workspaceCommands)
        return Array(commands.prefix(8))
    }

    private func fixedCommands() -> [PaletteCommand] {
        [
            PaletteCommand(
                id: UUID(),
                title: "Open Workspaces",
                subtitle: nil,
                icon: .sfSymbol("rectangle.3.group"),
                keywords: ["workspace", "open", "panel"],
                action: .push(.workspaces),
                category: "Workspace"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Save Current Workspace",
                subtitle: nil,
                icon: .sfSymbol("square.and.arrow.down"),
                keywords: ["workspace", "save", "current", "layout"],
                action: .execute { [onSaveCurrent] in onSaveCurrent() },
                category: "Workspace"
            ),
        ]
    }
}
```

- [ ] **Step 4: Add the workspace palette destination**

In `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`, update `PaletteDestination` to:

```swift
enum PaletteDestination: Equatable {
    case windowPicker
    case screenshotLibrary
    case portLookup
    case workspaces
}
```

- [ ] **Step 5: Add workspace push view support to CommandPaletteView**

In `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`, add this property near the existing view builders:

```swift
var workspaceViewBuilder: (() -> AnyView)?
```

In `CommandPaletteController.show()`, pass the builder into `CommandPaletteView` by changing the initializer call to include:

```swift
workspaceViewBuilder: workspaceViewBuilder
```

In `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`, add this property near the existing injected view builders:

```swift
let workspaceViewBuilder: (() -> AnyView)?
```

Update `CommandPaletteView.init(...)` by adding this parameter after `windowPickerViewBuilder`:

```swift
workspaceViewBuilder: (() -> AnyView)? = nil
```

Assign it in the initializer:

```swift
self.workspaceViewBuilder = workspaceViewBuilder
```

Update `subView(for:)` with the new destination:

```swift
@ViewBuilder
private func subView(for dest: PaletteDestination) -> some View {
    switch dest {
    case .screenshotLibrary:
        screenshotLibraryViewBuilder?() ?? AnyView(Text("Screenshot Library").padding())
    case .portLookup:
        portLookupViewBuilder?() ?? AnyView(Text("Port Lookup").padding())
    case .windowPicker:
        windowPickerViewBuilder?() ?? AnyView(Text("Window Picker").padding())
    case .workspaces:
        workspaceViewBuilder?() ?? AnyView(Text("Workspaces").padding())
    }
}
```

Do not add a `CommandPaletteController.push(...)` method. The existing architecture pushes destinations through `PaletteAction.push(PaletteDestination)`, and `CommandPaletteView.execute(_:)` appends the destination to its internal stack.

- [ ] **Step 6: Register the provider in AtlasApp**

In `platforms/macos/Atlas/AtlasApp.swift`, add these properties to `CommandPaletteState`:

```swift
private let workspaceStore = WorkspaceStore()
private let workspaceService = WorkspaceWindowService()
private let workspacePermissionChecker = AccessibilityPermissionChecker()
private var onSaveCurrentWorkspace: (() -> Void)?
private var onRestoreWorkspace: ((Workspace) -> Void)?
```

Create the provider before `self.controller = CommandPaletteController`:

```swift
let workspaceProvider = WorkspaceProvider(
    store: workspaceStore,
    isEnabled: { [weak self] in self?.isWindowManagementEnabled == true },
    onSaveCurrent: { [weak self] in self?.onSaveCurrentWorkspace?() },
    onRestore: { [weak self] workspace in self?.onRestoreWorkspace?(workspace) }
)
```

Insert `workspaceProvider` after `windowManagementProvider` in the providers array.

Add this method to `CommandPaletteState`:

```swift
func setWorkspaceActions(
    onSaveCurrent: @escaping () -> Void,
    onRestore: @escaping (Workspace) -> Void
) {
    onSaveCurrentWorkspace = onSaveCurrent
    onRestoreWorkspace = onRestore
}
```

- [ ] **Step 7: Add provider files to the Xcode project**

Run this exact script from the repository root:

```bash
ruby <<'RUBY'
require 'xcodeproj'

project_path = 'platforms/macos/Atlas.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |target| target.name == 'Atlas' }
test_target = project.targets.find { |target| target.name == 'AtlasTests' }
command_group = project.main_group['Atlas']['CommandPalette']
tests_group = project.main_group['AtlasTests']

abort('Atlas target not found') unless app_target
abort('AtlasTests target not found') unless test_target
abort('CommandPalette group not found') unless command_group
abort('AtlasTests group not found') unless tests_group

[
  [command_group, app_target, 'WorkspaceProvider.swift'],
  [tests_group, test_target, 'WorkspaceProviderTests.swift'],
].each do |group, target, path|
  file_ref = group.files.find { |file| file.path == path } || group.new_file(path)
  target.add_file_references([file_ref]) unless target.source_build_phase.files_references.include?(file_ref)
end

project.save
RUBY
```

- [ ] **Step 8: Run provider tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspaceProviderTests
```

Expected: PASS.

---

### Task 6: ContentView Integration and Feature Gating

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Verify: `platforms/macos/Atlas/AtlasApp.swift`

- [ ] **Step 1: Add workspace dependencies to ContentView**

In `platforms/macos/Atlas/ContentView.swift`, add these properties near the existing stores:

```swift
private let workspaceStore = WorkspaceStore()
private let workspaceService = WorkspaceWindowService()
private let workspacePermissionChecker = AccessibilityPermissionChecker()
```

- [ ] **Step 2: Show the panel when Window Manager is enabled**

In `ContentView.body`, insert this block after `WindowGridPanel` and before `FeatureCenterPanel`:

```swift
if isFeatureEnabled(.windowManager) {
    WorkspacePanel(
        model: WorkspacePanelModel(
            store: workspaceStore,
            service: workspaceService,
            permissionChecker: workspacePermissionChecker,
            isFeatureEnabled: { isFeatureEnabled(.windowManager) }
        )
    )

    Divider()
}
```

- [ ] **Step 3: Wire command palette view builder and actions**

In `ContentView.startHotkeys()`, after existing controller view builders are configured, add:

```swift
controller.workspaceViewBuilder = {
    AnyView(
        WorkspacePanel(
            model: WorkspacePanelModel(
                store: workspaceStore,
                service: workspaceService,
                permissionChecker: workspacePermissionChecker,
                isFeatureEnabled: { isFeatureEnabled(.windowManager) }
            )
        )
    )
}

paletteState?.setWorkspaceActions(
    onSaveCurrent: {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let name = "Workspace \(formatter.string(from: Date()))"
        let model = WorkspacePanelModel(
            store: workspaceStore,
            service: workspaceService,
            permissionChecker: workspacePermissionChecker,
            isFeatureEnabled: { isFeatureEnabled(.windowManager) }
        )
        do {
            try model.saveCurrentLayout(named: name)
            showStatus(model.statusMessage)
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    },
    onRestore: { workspace in
        let model = WorkspacePanelModel(
            store: workspaceStore,
            service: workspaceService,
            permissionChecker: workspacePermissionChecker,
            isFeatureEnabled: { isFeatureEnabled(.windowManager) }
        )
        do {
            try model.restore(workspace)
            let hasIssues = !model.restoreIssues.isEmpty || model.statusMessage == "Accessibility permission is required"
            showStatus(model.statusMessage, kind: hasIssues ? .error : .success)
        } catch {
            showStatus(error.localizedDescription, kind: .error)
        }
    }
)
```

Expected behavior: `Open Workspaces` uses `PaletteAction.push(.workspaces)` and renders through `CommandPaletteView.subView(for:)`. Save and restore command actions surface `WorkspacePanelModel.statusMessage`; they must not report a successful save or restore when Accessibility permission is missing.

- [ ] **Step 4: Run focused workspace tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspaceModelsTests -only-testing:AtlasTests/WorkspaceStoreTests -only-testing:AtlasTests/WorkspaceWindowServiceTests -only-testing:AtlasTests/WorkspacePanelTests -only-testing:AtlasTests/WorkspaceProviderTests
```

Expected: PASS.

---

### Task 7: Final Verification and Commit

**Files:**
- Verify: `platforms/macos/Atlas/WorkspaceModels.swift`
- Verify: `platforms/macos/Atlas/WorkspaceStore.swift`
- Verify: `platforms/macos/Atlas/WorkspaceWindowService.swift`
- Verify: `platforms/macos/Atlas/WorkspacePanel.swift`
- Verify: `platforms/macos/Atlas/CommandPalette/WorkspaceProvider.swift`
- Verify: `platforms/macos/Atlas/ContentView.swift`
- Verify: `platforms/macos/Atlas/AtlasApp.swift`
- Verify: `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`
- Verify: `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`
- Verify: `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`
- Verify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Run the focused test suite**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WorkspaceModelsTests -only-testing:AtlasTests/WorkspaceStoreTests -only-testing:AtlasTests/WorkspaceWindowServiceTests -only-testing:AtlasTests/WorkspacePanelTests -only-testing:AtlasTests/WorkspaceProviderTests -only-testing:AtlasTests/WindowManagementProviderTests
```

Expected: PASS.

- [ ] **Step 2: Run the broader macOS XCTest suite**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: PASS. Non-blocking CoreSimulator warnings are acceptable when the macOS tests still finish with `** TEST SUCCEEDED **`.

- [ ] **Step 3: Review changed files**

Run:

```bash
git diff -- platforms/macos/Atlas/WorkspaceModels.swift platforms/macos/Atlas/WorkspaceStore.swift platforms/macos/Atlas/WorkspaceWindowService.swift platforms/macos/Atlas/WorkspacePanel.swift platforms/macos/Atlas/CommandPalette/WorkspaceProvider.swift platforms/macos/Atlas/ContentView.swift platforms/macos/Atlas/AtlasApp.swift platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift platforms/macos/AtlasTests/WorkspaceModelsTests.swift platforms/macos/AtlasTests/WorkspaceStoreTests.swift platforms/macos/AtlasTests/WorkspaceWindowServiceTests.swift platforms/macos/AtlasTests/WorkspacePanelTests.swift platforms/macos/AtlasTests/WorkspaceProviderTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: Diff contains only workspace models, persistence, capture/restore, panel, command palette actions, tests, and PBX membership changes.

- [ ] **Step 4: Commit**

Run:

```bash
git add platforms/macos/Atlas/WorkspaceModels.swift platforms/macos/Atlas/WorkspaceStore.swift platforms/macos/Atlas/WorkspaceWindowService.swift platforms/macos/Atlas/WorkspacePanel.swift platforms/macos/Atlas/CommandPalette/WorkspaceProvider.swift platforms/macos/Atlas/ContentView.swift platforms/macos/Atlas/AtlasApp.swift platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift platforms/macos/AtlasTests/WorkspaceModelsTests.swift platforms/macos/AtlasTests/WorkspaceStoreTests.swift platforms/macos/AtlasTests/WorkspaceWindowServiceTests.swift platforms/macos/AtlasTests/WorkspacePanelTests.swift platforms/macos/AtlasTests/WorkspaceProviderTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: add workspaces"
```

Expected: Commit includes workspace capture, named save, restore, missing app/window reporting, command palette actions, Feature Center gating, injected snapshot tests, and explicit Xcode project membership updates.

## Self-Review

- Spec coverage: capture current layout is Task 3 and Task 4; save named workspace is Task 2 and Task 4; restore layout is Task 3 and Task 4; missing app/window behavior is Task 1 and Task 3; command palette actions are Task 5 and Task 6; Feature Center gating is Task 5 and Task 6; injected window snapshots are Task 3 and Task 4.
- Red-flag scan: no banned planning shortcuts are present.
- Type consistency: `Workspace`, `WorkspaceWindow`, `WorkspaceStore`, `WorkspaceWindowService`, `WorkspacePanelModel`, and `WorkspaceProvider` are defined before later tasks use them.
