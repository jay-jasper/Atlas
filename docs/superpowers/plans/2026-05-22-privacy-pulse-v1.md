# Privacy Pulse v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Feature Center gated Privacy Pulse panel that shows Atlas privacy access status and recent Atlas-internal privacy access events.

**Architecture:** Keep v1 in the macOS Swift layer because it depends on AppKit, AVFoundation, CoreGraphics, and Accessibility status APIs. Production code reads only public permission/status APIs and Atlas-internal access logs; tests use injected event sources and never open camera or microphone sessions, read the real pasteboard, call permission request APIs, or mutate System Settings. Clipboard, screen recording, and Accessibility access events are recorded at Atlas boundaries where Atlas already performs those actions.

**Tech Stack:** Swift, SwiftUI, AppKit `NSPasteboard` abstraction, AVFoundation authorization status APIs, CoreGraphics screen capture preflight API, ApplicationServices Accessibility trust API, XCTest, Rust Feature Center registry, UniFFI feature list, explicit Xcode PBX project membership.

---

## Scope

This plan implements:

- Visible status rows for camera permission, microphone permission, Atlas clipboard reads, screen recording permission, and Atlas Accessibility use.
- A recent event list for Atlas-internal privacy accesses.
- A small injected privacy event source boundary for tests.
- Atlas-internal access logging for clipboard reads/writes, screenshot capture attempts, screen recording permission checks, Accessibility window actions, and hotkey Accessibility checks.
- Feature Center gating through a new `privacy` feature flag, disabled by default.
- Deterministic XCTest coverage that uses fake status providers and fake event stores.
- Explicit Xcode project membership updates for all new Swift app and test files.

Out of scope:

- Detecting other apps' camera, microphone, clipboard, screen recording, or Accessibility usage.
- Opening camera or microphone capture sessions.
- Requesting camera, microphone, screen recording, or Accessibility permissions from Privacy Pulse tests.
- Persisting raw clipboard contents, screenshots, window titles, or process arguments in privacy events.
- Rust or UniFFI APIs beyond registering the `privacy` feature name.

## Current Baseline

The required audit command:

```bash
rg -n 'privacy|camera|microphone|pasteboard|clipboard|permission|Screen Recording|Accessibility' platforms/macos/Atlas platforms/macos/AtlasTests docs/superpowers/plans
```

shows:

- `platforms/macos/Atlas/GlobalHotkeyService.swift` requests Accessibility for global hotkeys.
- `platforms/macos/Atlas/ContentView.swift` calls `hotkeyService.requestAccessibilityIfNeeded()` and writes text to `NSPasteboard.general` from screenshot library/OCR flows.
- `platforms/macos/Atlas/WindowManagementService.swift` uses Accessibility APIs for focused-window mutation.
- `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift` reads and writes `NSPasteboard` through the `ClipboardReading` protocol.
- `platforms/macos/Atlas/ScreenshotOutput.swift` writes screenshot PNG data to the pasteboard.
- Existing child plans discuss Screen Recording, Accessibility, camera, and clipboard permission behavior.

There is no current Privacy Pulse production surface and no central Atlas-internal privacy access log.

## File Map

**New files:**

- `platforms/macos/Atlas/PrivacyPulseModels.swift`
  - Defines `PrivacyPulseCategory`, `PrivacyPulseStatus`, `PrivacyPulseEvent`, `PrivacyPulseSnapshot`, `PrivacyPulseEventStoring`, and `PrivacyPulseStatusProviding`.
- `platforms/macos/Atlas/PrivacyPulseService.swift`
  - Combines injected status providers and event store snapshots for the panel.
- `platforms/macos/Atlas/PrivacyPulsePanel.swift`
  - SwiftUI panel for visible status and recent Atlas access events.
- `platforms/macos/Atlas/PrivacyPulseAccessLogger.swift`
  - Defines the shared Atlas-internal logging protocol and in-memory implementation.
- `platforms/macos/Atlas/PrivacyPulseSystemStatusProvider.swift`
  - Reads public camera/microphone authorization status, screen recording preflight status, and Accessibility trust status.
- `platforms/macos/AtlasTests/PrivacyPulseServiceTests.swift`
- `platforms/macos/AtlasTests/PrivacyPulsePanelTests.swift`

**Modified files:**

- `crates/atlas-core/src/features.rs`
  - Registers `privacy` disabled by default and updates sorted feature coverage additively.
- `platforms/macos/Atlas/AtlasModule.swift`
  - Adds `case privacy` and the visible title `Privacy Pulse` additively.
- `platforms/macos/Atlas/FeatureModels.swift`
  - Maps the `privacy` feature name to `Privacy Pulse`.
- `platforms/macos/Atlas/ContentView.swift`
  - Shows `PrivacyPulsePanel` only when the `privacy` feature is enabled and wires the shared logger/status provider.
- `platforms/macos/Atlas/AtlasApp.swift`
  - Owns one shared `PrivacyPulseAccessLogger`, passes it into command providers, and exposes it to `ContentView`.
- `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift`
  - Logs clipboard read and write events through an optional injected logger.
- `platforms/macos/Atlas/CommandPalette/SnippetsProvider.swift`
  - Logs snippet clipboard writes through an optional injected logger.
- `platforms/macos/Atlas/ScreenshotOutput.swift`
  - Logs screenshot pasteboard writes through an optional injected logger.
- `platforms/macos/Atlas/WindowManagementService.swift`
  - Logs Accessibility window action attempts through an optional injected logger.
- `platforms/macos/Atlas/GlobalHotkeyService.swift`
  - Logs Accessibility trust checks through an optional injected logger.
- `platforms/macos/AtlasTests/FeatureModelsTests.swift`
  - Adds Privacy Pulse title coverage.
- `platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift`
  - Verifies fake logger receives clipboard read/write events without touching the real pasteboard.
- `platforms/macos/AtlasTests/SnippetsProviderTests.swift`
  - Updates fake clipboard tests for injected logging.
- `platforms/macos/AtlasTests/WindowManagementServiceTests.swift`
  - Verifies Accessibility logging through fake/injected boundaries where available.
- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds every new Swift app file to the `Atlas` target sources and every new Swift test file to the `AtlasTests` target sources.

Project membership rule: this repo uses explicit PBX project references. Every new Swift file listed above must appear as a `PBXFileReference`, a `PBXBuildFile`, in the correct group, and in the correct `PBXSourcesBuildPhase` before running `xcodebuild test`.

---

### Task 1: Register Privacy Feature Gate

**Files:**
- Modify: `crates/atlas-core/src/features.rs`
- Modify: `platforms/macos/Atlas/AtlasModule.swift`
- Modify: `platforms/macos/Atlas/FeatureModels.swift`
- Test: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

- [ ] **Step 1: Add Rust feature registration**

In `crates/atlas-core/src/features.rs`, add the privacy feature inside `FeatureManager::new()`:

```rust
features.insert("privacy".to_string(), FeatureStatus::Disabled);
```

Do not replace the existing set with a closed list. Insert only the new registration and preserve adjacent child-plan features such as `clipboard`, `scratchpad`, `system-utilities`, `tokenbar`, and `ai-load-monitor` when they are already present.

Update `test_list_features_is_sorted_by_name` additively:

```rust
#[test]
fn test_list_features_is_sorted_by_name() {
    let fm = FeatureManager::new();
    let names: Vec<_> = fm.list_features().into_iter().map(|(name, _)| name).collect();

    assert!(names.contains(&"privacy".to_string()));
    assert!(names.windows(2).all(|pair| pair[0] <= pair[1]));
}
```

- [ ] **Step 2: Add Swift module case additively**

In `platforms/macos/Atlas/AtlasModule.swift`, add `privacy` without removing existing or adjacent child-plan cases:

```swift
enum AtlasModule: String, CaseIterable, Identifiable {
    case screenshot
    case monitoring
    case privacy

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
        case .privacy:
            return "Privacy Pulse"
        }
    }
}
```

If other child plans have already added cases, keep them in the enum and add only the `privacy` case plus its `switch` branch.

- [ ] **Step 3: Map Privacy Pulse feature title**

In `platforms/macos/Atlas/FeatureModels.swift`, add the title branch without changing fallback behavior:

```swift
private enum AtlasFeatureTitles {
    static func title(for name: String) -> String {
        switch name {
        case AtlasModule.monitoring.featureName:
            return AtlasModule.monitoring.title
        case AtlasModule.privacy.featureName:
            return AtlasModule.privacy.title
        case AtlasModule.screenshot.featureName:
            return AtlasModule.screenshot.title
        default:
            return name
                .split(separator: "-")
                .map { word in
                    word.prefix(1).uppercased() + word.dropFirst()
                }
                .joined(separator: " ")
        }
    }
}
```

- [ ] **Step 4: Add focused feature title test**

In `platforms/macos/AtlasTests/FeatureModelsTests.swift`, add:

```swift
func testPrivacyFeatureTitleUsesProductName() {
    let feature = AtlasFeature(name: "privacy", isEnabled: false)

    XCTAssertEqual(feature.title, "Privacy Pulse")
}
```

- [ ] **Step 5: Verify feature gate**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureModelsTests
```

Expected: Both commands pass. The Rust test confirms `privacy` exists and names remain sorted; Swift title tests pass.

- [ ] **Step 6: Commit feature gate**

Run:

```bash
git add crates/atlas-core/src/features.rs platforms/macos/Atlas/AtlasModule.swift platforms/macos/Atlas/FeatureModels.swift platforms/macos/AtlasTests/FeatureModelsTests.swift
git commit -m "feat: register Privacy Pulse feature"
```

Expected: The commit contains only feature registration and title-test changes.

---

### Task 2: Add Privacy Pulse Models and In-Memory Log

**Files:**
- Create: `platforms/macos/Atlas/PrivacyPulseModels.swift`
- Create: `platforms/macos/Atlas/PrivacyPulseAccessLogger.swift`
- Test: `platforms/macos/AtlasTests/PrivacyPulseServiceTests.swift`

- [ ] **Step 1: Create shared models**

Create `platforms/macos/Atlas/PrivacyPulseModels.swift`:

```swift
import Foundation

enum PrivacyPulseCategory: String, CaseIterable, Identifiable, Sendable {
    case camera
    case microphone
    case clipboard
    case screenRecording
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera:
            return "Camera"
        case .microphone:
            return "Microphone"
        case .clipboard:
            return "Clipboard"
        case .screenRecording:
            return "Screen Recording"
        case .accessibility:
            return "Accessibility"
        }
    }
}

enum PrivacyPulseStatus: Equatable, Sendable {
    case allowed
    case denied
    case notDetermined
    case recentlyUsed(Date)
    case inactive

    var label: String {
        switch self {
        case .allowed:
            return "Allowed"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Determined"
        case .recentlyUsed:
            return "Recently Used"
        case .inactive:
            return "Inactive"
        }
    }
}

struct PrivacyPulseEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let category: PrivacyPulseCategory
    let title: String
    let detail: String
    let occurredAt: Date
}

struct PrivacyPulseSnapshot: Equatable, Sendable {
    let statuses: [PrivacyPulseCategory: PrivacyPulseStatus]
    let events: [PrivacyPulseEvent]

    func status(for category: PrivacyPulseCategory) -> PrivacyPulseStatus {
        statuses[category] ?? .inactive
    }
}

protocol PrivacyPulseEventStoring {
    func record(_ event: PrivacyPulseEvent)
    func recentEvents(limit: Int) -> [PrivacyPulseEvent]
    func mostRecentEventDate(for category: PrivacyPulseCategory) -> Date?
}

protocol PrivacyPulseStatusProviding {
    func cameraStatus() -> PrivacyPulseStatus
    func microphoneStatus() -> PrivacyPulseStatus
    func screenRecordingStatus() -> PrivacyPulseStatus
    func accessibilityStatus() -> PrivacyPulseStatus
}
```

- [ ] **Step 2: Create shared Atlas access logger**

Create `platforms/macos/Atlas/PrivacyPulseAccessLogger.swift`:

```swift
import Foundation

protocol PrivacyPulseAccessLogging {
    func record(category: PrivacyPulseCategory, title: String, detail: String)
}

final class PrivacyPulseAccessLogger: PrivacyPulseAccessLogging, PrivacyPulseEventStoring {
    private let maxEvents: Int
    private let dateProvider: () -> Date
    private let lock = NSLock()
    private var events: [PrivacyPulseEvent] = []

    init(maxEvents: Int = 100, dateProvider: @escaping () -> Date = Date.init) {
        self.maxEvents = maxEvents
        self.dateProvider = dateProvider
    }

    func record(category: PrivacyPulseCategory, title: String, detail: String) {
        record(
            PrivacyPulseEvent(
                id: UUID(),
                category: category,
                title: title,
                detail: detail,
                occurredAt: dateProvider()
            )
        )
    }

    func record(_ event: PrivacyPulseEvent) {
        lock.lock()
        defer { lock.unlock() }

        events.insert(event, at: 0)
        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }
    }

    func recentEvents(limit: Int) -> [PrivacyPulseEvent] {
        lock.lock()
        defer { lock.unlock() }

        return Array(events.prefix(max(0, limit)))
    }

    func mostRecentEventDate(for category: PrivacyPulseCategory) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        return events.first { $0.category == category }?.occurredAt
    }
}

struct NoopPrivacyPulseAccessLogger: PrivacyPulseAccessLogging {
    func record(category: PrivacyPulseCategory, title: String, detail: String) {}
}
```

- [ ] **Step 3: Add in-memory logger tests**

Create `platforms/macos/AtlasTests/PrivacyPulseServiceTests.swift` with the first focused tests:

```swift
import XCTest
@testable import Atlas

final class PrivacyPulseServiceTests: XCTestCase {
    func testLoggerStoresMostRecentEventsFirstAndTrims() {
        var now = Date(timeIntervalSince1970: 100)
        let logger = PrivacyPulseAccessLogger(maxEvents: 2, dateProvider: { now })

        logger.record(category: .clipboard, title: "Clipboard Read", detail: "Clipboard history checked for text")
        now = Date(timeIntervalSince1970: 101)
        logger.record(category: .accessibility, title: "Accessibility Check", detail: "Global hotkey trust checked")
        now = Date(timeIntervalSince1970: 102)
        logger.record(category: .screenRecording, title: "Screen Capture", detail: "Desktop capture requested")

        let events = logger.recentEvents(limit: 10)

        XCTAssertEqual(events.map(\.category), [.screenRecording, .accessibility])
        XCTAssertEqual(logger.mostRecentEventDate(for: .screenRecording), Date(timeIntervalSince1970: 102))
        XCTAssertNil(logger.mostRecentEventDate(for: .camera))
    }
}
```

- [ ] **Step 4: Verify logger tests fail before project membership**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/PrivacyPulseServiceTests
```

Expected: The command fails because the new Swift files are not yet members of the Xcode project. This confirms the explicit PBX membership step is required.

- [ ] **Step 5: Add Xcode project membership for initial files**

Update `platforms/macos/Atlas.xcodeproj/project.pbxproj` so these files are in the correct targets:

```text
Atlas target sources:
- PrivacyPulseModels.swift
- PrivacyPulseAccessLogger.swift

AtlasTests target sources:
- PrivacyPulseServiceTests.swift
```

Use the existing PBX style in the file: one `PBXFileReference`, one `PBXBuildFile`, one group entry, and one `PBXSourcesBuildPhase` entry per Swift source.

- [ ] **Step 6: Verify logger tests pass**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/PrivacyPulseServiceTests
```

Expected: `PrivacyPulseServiceTests/testLoggerStoresMostRecentEventsFirstAndTrims` passes without reading the clipboard or touching system permissions.

- [ ] **Step 7: Commit models and logger**

Run:

```bash
git add platforms/macos/Atlas/PrivacyPulseModels.swift platforms/macos/Atlas/PrivacyPulseAccessLogger.swift platforms/macos/AtlasTests/PrivacyPulseServiceTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: add Privacy Pulse event log"
```

Expected: The commit contains only the shared models, in-memory logger, first tests, and PBX membership.

---

### Task 3: Add Injected Status Provider and Service Snapshot

**Files:**
- Create: `platforms/macos/Atlas/PrivacyPulseSystemStatusProvider.swift`
- Create/Modify: `platforms/macos/Atlas/PrivacyPulseService.swift`
- Modify: `platforms/macos/AtlasTests/PrivacyPulseServiceTests.swift`

- [ ] **Step 1: Add public system status provider**

Create `platforms/macos/Atlas/PrivacyPulseSystemStatusProvider.swift`:

```swift
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

struct PrivacyPulseSystemStatusProvider: PrivacyPulseStatusProviding {
    func cameraStatus() -> PrivacyPulseStatus {
        status(from: AVCaptureDevice.authorizationStatus(for: .video))
    }

    func microphoneStatus() -> PrivacyPulseStatus {
        status(from: AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func screenRecordingStatus() -> PrivacyPulseStatus {
        CGPreflightScreenCaptureAccess() ? .allowed : .denied
    }

    func accessibilityStatus() -> PrivacyPulseStatus {
        AXIsProcessTrusted() ? .allowed : .denied
    }

    private func status(from authorizationStatus: AVAuthorizationStatus) -> PrivacyPulseStatus {
        switch authorizationStatus {
        case .authorized:
            return .allowed
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }
}
```

This provider must not call `AVCaptureDevice.requestAccess`, create `AVCaptureSession`, call `CGRequestScreenCaptureAccess`, or prompt for Accessibility.

- [ ] **Step 2: Add service snapshot composition**

Create `platforms/macos/Atlas/PrivacyPulseService.swift`:

```swift
import Foundation

final class PrivacyPulseService {
    private let statusProvider: PrivacyPulseStatusProviding
    private let eventStore: PrivacyPulseEventStoring
    private let recentUsageInterval: TimeInterval

    init(
        statusProvider: PrivacyPulseStatusProviding,
        eventStore: PrivacyPulseEventStoring,
        recentUsageInterval: TimeInterval = 300
    ) {
        self.statusProvider = statusProvider
        self.eventStore = eventStore
        self.recentUsageInterval = recentUsageInterval
    }

    func snapshot(now: Date = Date(), eventLimit: Int = 20) -> PrivacyPulseSnapshot {
        PrivacyPulseSnapshot(
            statuses: [
                .camera: statusProvider.cameraStatus(),
                .microphone: statusProvider.microphoneStatus(),
                .clipboard: derivedStatus(for: .clipboard, now: now),
                .screenRecording: mergedStatus(
                    permissionStatus: statusProvider.screenRecordingStatus(),
                    category: .screenRecording,
                    now: now
                ),
                .accessibility: mergedStatus(
                    permissionStatus: statusProvider.accessibilityStatus(),
                    category: .accessibility,
                    now: now
                ),
            ],
            events: eventStore.recentEvents(limit: eventLimit)
        )
    }

    private func derivedStatus(for category: PrivacyPulseCategory, now: Date) -> PrivacyPulseStatus {
        guard let date = eventStore.mostRecentEventDate(for: category) else {
            return .inactive
        }
        return now.timeIntervalSince(date) <= recentUsageInterval ? .recentlyUsed(date) : .inactive
    }

    private func mergedStatus(
        permissionStatus: PrivacyPulseStatus,
        category: PrivacyPulseCategory,
        now: Date
    ) -> PrivacyPulseStatus {
        if case .allowed = permissionStatus,
           let date = eventStore.mostRecentEventDate(for: category),
           now.timeIntervalSince(date) <= recentUsageInterval {
            return .recentlyUsed(date)
        }
        return permissionStatus
    }
}
```

- [ ] **Step 3: Extend service tests with injected fakes**

Append to `platforms/macos/AtlasTests/PrivacyPulseServiceTests.swift`:

```swift
func testSnapshotUsesInjectedStatusProviderAndRecentAtlasEvents() {
    let now = Date(timeIntervalSince1970: 1_000)
    let store = PrivacyPulseAccessLogger(dateProvider: { now })
    store.record(category: .clipboard, title: "Clipboard Read", detail: "Clipboard history checked for text")
    store.record(category: .accessibility, title: "Accessibility Check", detail: "Global hotkey trust checked")
    let service = PrivacyPulseService(
        statusProvider: FakePrivacyStatusProvider(
            camera: .notDetermined,
            microphone: .denied,
            screenRecording: .allowed,
            accessibility: .allowed
        ),
        eventStore: store,
        recentUsageInterval: 300
    )

    let snapshot = service.snapshot(now: now, eventLimit: 10)

    XCTAssertEqual(snapshot.status(for: .camera), .notDetermined)
    XCTAssertEqual(snapshot.status(for: .microphone), .denied)
    XCTAssertEqual(snapshot.status(for: .screenRecording), .allowed)
    XCTAssertEqual(snapshot.status(for: .clipboard), .recentlyUsed(now))
    XCTAssertEqual(snapshot.status(for: .accessibility), .recentlyUsed(now))
    XCTAssertEqual(snapshot.events.count, 2)
}

func testSnapshotMarksOldInternalEventsInactive() {
    let eventDate = Date(timeIntervalSince1970: 1_000)
    let now = Date(timeIntervalSince1970: 2_000)
    let store = PrivacyPulseAccessLogger(dateProvider: { eventDate })
    store.record(category: .clipboard, title: "Clipboard Read", detail: "Clipboard history checked for text")
    let service = PrivacyPulseService(
        statusProvider: FakePrivacyStatusProvider(
            camera: .allowed,
            microphone: .allowed,
            screenRecording: .allowed,
            accessibility: .allowed
        ),
        eventStore: store,
        recentUsageInterval: 300
    )

    let snapshot = service.snapshot(now: now, eventLimit: 10)

    XCTAssertEqual(snapshot.status(for: .clipboard), .inactive)
}

private struct FakePrivacyStatusProvider: PrivacyPulseStatusProviding {
    let camera: PrivacyPulseStatus
    let microphone: PrivacyPulseStatus
    let screenRecording: PrivacyPulseStatus
    let accessibility: PrivacyPulseStatus

    func cameraStatus() -> PrivacyPulseStatus { camera }
    func microphoneStatus() -> PrivacyPulseStatus { microphone }
    func screenRecordingStatus() -> PrivacyPulseStatus { screenRecording }
    func accessibilityStatus() -> PrivacyPulseStatus { accessibility }
}
```

- [ ] **Step 4: Add PBX membership for service files**

Update `platforms/macos/Atlas.xcodeproj/project.pbxproj`:

```text
Atlas target sources:
- PrivacyPulseSystemStatusProvider.swift
- PrivacyPulseService.swift
```

- [ ] **Step 5: Verify service tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/PrivacyPulseServiceTests
```

Expected: All Privacy Pulse service tests pass. The tests use `FakePrivacyStatusProvider` and `PrivacyPulseAccessLogger`; they do not open real camera/microphone sessions, read the real clipboard, call permission request APIs, or change real permissions.

- [ ] **Step 6: Commit status provider and service**

Run:

```bash
git add platforms/macos/Atlas/PrivacyPulseSystemStatusProvider.swift platforms/macos/Atlas/PrivacyPulseService.swift platforms/macos/AtlasTests/PrivacyPulseServiceTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: add Privacy Pulse status snapshot"
```

Expected: The commit contains only Privacy Pulse status provider, service, tests, and PBX membership.

---

### Task 4: Add Privacy Pulse Panel

**Files:**
- Create: `platforms/macos/Atlas/PrivacyPulsePanel.swift`
- Create: `platforms/macos/AtlasTests/PrivacyPulsePanelTests.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Create SwiftUI panel**

Create `platforms/macos/Atlas/PrivacyPulsePanel.swift`:

```swift
import SwiftUI

struct PrivacyPulsePanel: View {
    let snapshot: PrivacyPulseSnapshot
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Privacy Pulse")
                    .font(.headline)
                Spacer()
                Button("Refresh", action: onRefresh)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(PrivacyPulseCategory.allCases) { category in
                    PrivacyPulseStatusRow(
                        category: category,
                        status: snapshot.status(for: category)
                    )
                }
            }

            Divider()

            Text("Recent Atlas Access")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if snapshot.events.isEmpty {
                Text("No Atlas privacy access recorded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(snapshot.events) { event in
                    PrivacyPulseEventRow(event: event)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrivacyPulseStatusRow: View {
    let category: PrivacyPulseCategory
    let status: PrivacyPulseStatus

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .frame(width: 18)
            Text(category.title)
            Spacer()
            Text(status.label)
                .foregroundStyle(statusColor)
        }
        .font(.subheadline)
    }

    private var iconName: String {
        switch category {
        case .camera:
            return "camera"
        case .microphone:
            return "mic"
        case .clipboard:
            return "doc.on.clipboard"
        case .screenRecording:
            return "rectangle.dashed"
        case .accessibility:
            return "accessibility"
        }
    }

    private var statusColor: Color {
        switch status {
        case .allowed, .recentlyUsed:
            return .green
        case .denied:
            return .red
        case .notDetermined, .inactive:
            return .secondary
        }
    }
}

private struct PrivacyPulseEventRow: View {
    let event: PrivacyPulseEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(event.title)
                    .font(.subheadline)
                Spacer()
                Text(event.category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(event.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: Add panel renderer tests**

Create `platforms/macos/AtlasTests/PrivacyPulsePanelTests.swift`:

```swift
import XCTest
@testable import Atlas

final class PrivacyPulsePanelTests: XCTestCase {
    func testSnapshotContainsAllVisiblePrivacyCategories() {
        let event = PrivacyPulseEvent(
            id: UUID(),
            category: .clipboard,
            title: "Clipboard Read",
            detail: "Clipboard history checked for text",
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let snapshot = PrivacyPulseSnapshot(
            statuses: [
                .camera: .notDetermined,
                .microphone: .denied,
                .clipboard: .recentlyUsed(event.occurredAt),
                .screenRecording: .allowed,
                .accessibility: .inactive,
            ],
            events: [event]
        )

        XCTAssertEqual(PrivacyPulseCategory.allCases.map(\.title), [
            "Camera",
            "Microphone",
            "Clipboard",
            "Screen Recording",
            "Accessibility",
        ])
        XCTAssertEqual(snapshot.status(for: .clipboard).label, "Recently Used")
        XCTAssertEqual(snapshot.events.first?.detail, "Clipboard history checked for text")
    }
}
```

This test intentionally validates the model data rendered by `PrivacyPulsePanel` without launching UI automation or touching protected system resources.

- [ ] **Step 3: Wire panel into ContentView behind Feature Center**

In `platforms/macos/Atlas/ContentView.swift`, add state and dependencies:

```swift
@State private var privacyPulseSnapshot = PrivacyPulseSnapshot(statuses: [:], events: [])
var privacyPulseService: PrivacyPulseService? = nil
```

In `body`, place the panel after Monitoring and before Feature Center:

```swift
if isFeatureEnabled(.privacy), let privacyPulseService {
    PrivacyPulsePanel(
        snapshot: privacyPulseSnapshot,
        onRefresh: { refreshPrivacyPulse(using: privacyPulseService) }
    )

    Divider()
}
```

In `startModules()`, refresh only when the feature is enabled:

```swift
if isFeatureEnabled(.privacy), let privacyPulseService {
    refreshPrivacyPulse(using: privacyPulseService)
}
```

In `handleFeatureChange(_:,enabled:)`, refresh when Privacy Pulse is enabled:

```swift
if feature == AtlasModule.privacy.featureName, enabled, let privacyPulseService {
    refreshPrivacyPulse(using: privacyPulseService)
}
```

Add the helper:

```swift
private func refreshPrivacyPulse(using service: PrivacyPulseService) {
    privacyPulseSnapshot = service.snapshot()
}
```

Preserve adjacent child-plan panels and builders already in `ContentView.swift`; add only Privacy Pulse state, panel placement, and refresh logic.

- [ ] **Step 4: Add PBX membership for panel files**

Update `platforms/macos/Atlas.xcodeproj/project.pbxproj`:

```text
Atlas target sources:
- PrivacyPulsePanel.swift

AtlasTests target sources:
- PrivacyPulsePanelTests.swift
```

- [ ] **Step 5: Verify panel tests and app build**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/PrivacyPulsePanelTests
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: The panel test and app build pass. Privacy Pulse is visible only when the `privacy` feature is enabled.

- [ ] **Step 6: Commit panel**

Run:

```bash
git add platforms/macos/Atlas/PrivacyPulsePanel.swift platforms/macos/AtlasTests/PrivacyPulsePanelTests.swift platforms/macos/Atlas/ContentView.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: show Privacy Pulse panel"
```

Expected: The commit contains only the panel, tests, ContentView gating, and PBX membership.

---

### Task 5: Log Atlas Clipboard and Pasteboard Access

**Files:**
- Modify: `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift`
- Modify: `platforms/macos/Atlas/CommandPalette/SnippetsProvider.swift`
- Modify: `platforms/macos/Atlas/ScreenshotOutput.swift`
- Modify: `platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift`
- Modify: `platforms/macos/AtlasTests/SnippetsProviderTests.swift`

- [ ] **Step 1: Log clipboard history reads and writes**

In `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift`, add a logger property and initializer parameter:

```swift
private let accessLogger: PrivacyPulseAccessLogging

init(
    reader: ClipboardReading = SystemClipboardReader(),
    maxHistoryCount: Int = 20,
    dateProvider: @escaping () -> Date = Date.init,
    accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
) {
    self.reader = reader
    self.maxHistoryCount = maxHistoryCount
    self.dateProvider = dateProvider
    self.accessLogger = accessLogger
}
```

In `captureCurrentClipboard()`, record before reading string data:

```swift
accessLogger.record(
    category: .clipboard,
    title: "Clipboard Read",
    detail: "Clipboard history checked for text"
)
guard let text = reader.string() else { return }
```

In the command action, capture the logger and record writes:

```swift
action: .execute { [reader, accessLogger] in
    accessLogger.record(
        category: .clipboard,
        title: "Clipboard Write",
        detail: "Clipboard history restored text to the pasteboard"
    )
    reader.setString(item.text)
},
```

- [ ] **Step 2: Log snippet clipboard writes**

In `platforms/macos/Atlas/CommandPalette/SnippetsProvider.swift`, add an optional logger parameter:

```swift
private let accessLogger: PrivacyPulseAccessLogging

init(
    store: SnippetStoring = SnippetStore(),
    clipboard: ClipboardReading = SystemClipboardReader(),
    accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
) {
    self.store = store
    self.clipboard = clipboard
    self.accessLogger = accessLogger
}
```

In the snippet execute action:

```swift
accessLogger.record(
    category: .clipboard,
    title: "Clipboard Write",
    detail: "Snippet copied text to the pasteboard"
)
clipboard.setString(snippet.body)
```

- [ ] **Step 3: Log screenshot pasteboard writes**

In `platforms/macos/Atlas/ScreenshotOutput.swift`, update `copyPNGToClipboard(_:)` with an optional logger parameter. Preserve the current call sites by defaulting the argument:

```swift
static func copyPNGToClipboard(
    _ data: Data,
    accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
) {
    let pasteboard = NSPasteboard.general
    accessLogger.record(
        category: .clipboard,
        title: "Clipboard Write",
        detail: "Screenshot copied PNG data to the pasteboard"
    )
    pasteboard.clearContents()
    pasteboard.setData(data, forType: .png)
}
```

- [ ] **Step 4: Add fake logger tests**

In `platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift`, add a fake logger and assertions:

```swift
final class FakePrivacyPulseAccessLogger: PrivacyPulseAccessLogging {
    private(set) var records: [(PrivacyPulseCategory, String, String)] = []

    func record(category: PrivacyPulseCategory, title: String, detail: String) {
        records.append((category, title, detail))
    }
}

func testCaptureLogsClipboardReadThroughInjectedLogger() {
    let reader = FakeClipboardReader(changeCount: 1, text: "secret")
    let logger = FakePrivacyPulseAccessLogger()
    let provider = ClipboardHistoryProvider(reader: reader, accessLogger: logger)

    provider.captureCurrentClipboard()

    XCTAssertEqual(logger.records.map(\.0), [.clipboard])
    XCTAssertEqual(logger.records.first?.1, "Clipboard Read")
}

func testExecutingClipboardResultLogsClipboardWrite() {
    let reader = FakeClipboardReader(changeCount: 1, text: "secret")
    let logger = FakePrivacyPulseAccessLogger()
    let provider = ClipboardHistoryProvider(reader: reader, accessLogger: logger)

    let command = provider.results(for: "secret").first
    guard case let .execute(action) = command?.action else {
        XCTFail("expected executable clipboard result")
        return
    }
    action()

    XCTAssertTrue(logger.records.contains { record in
        record.0 == .clipboard && record.1 == "Clipboard Write"
    })
}
```

Use the existing `PaletteCommand` execution helper in the test file. If the helper is named differently than `perform()`, call the existing helper and do not add UI automation.

- [ ] **Step 5: Verify clipboard tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/ClipboardHistoryProviderTests -only-testing:AtlasTests/SnippetsProviderTests -only-testing:AtlasTests/ScreenshotOutputTests
```

Expected: Tests pass using fake clipboard readers or explicit test pasteboards. They do not read the real general pasteboard except where pre-existing `ScreenshotOutputTests` already injects or controls the pasteboard boundary.

- [ ] **Step 6: Commit clipboard logging**

Run:

```bash
git add platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift platforms/macos/Atlas/CommandPalette/SnippetsProvider.swift platforms/macos/Atlas/ScreenshotOutput.swift platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift platforms/macos/AtlasTests/SnippetsProviderTests.swift
git commit -m "feat: log Atlas clipboard access"
```

Expected: The commit contains only Atlas clipboard/pasteboard access logging and related tests.

---

### Task 6: Log Screen Recording and Accessibility Use

**Files:**
- Modify: `platforms/macos/Atlas/AtlasCaptureService.swift`
- Modify: `platforms/macos/Atlas/WindowManagementService.swift`
- Modify: `platforms/macos/Atlas/GlobalHotkeyService.swift`
- Modify: `platforms/macos/AtlasTests/AtlasCaptureServiceTests.swift`
- Modify: `platforms/macos/AtlasTests/WindowManagementServiceTests.swift`
- Modify: `platforms/macos/AtlasTests/GlobalHotkeyServiceTests.swift`

- [ ] **Step 1: Log screen capture attempts through injected service dependencies**

In `platforms/macos/Atlas/AtlasCaptureService.swift`, add a logger dependency to the service initializer:

```swift
private let accessLogger: PrivacyPulseAccessLogging

init(
    bridge: AtlasCaptureBridge = AtlasBridgeCaptureBridge(),
    accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
) {
    self.bridge = bridge
    self.accessLogger = accessLogger
}
```

Before each desktop, window, or region capture bridge call, record a screen recording event:

```swift
accessLogger.record(
    category: .screenRecording,
    title: "Screen Capture",
    detail: "Atlas requested screen pixels for capture"
)
```

Do not call `CGRequestScreenCaptureAccess()` from tests or from this logging path.

- [ ] **Step 2: Log Accessibility window actions**

In `platforms/macos/Atlas/WindowManagementService.swift`, add a logger to `AccessibilityWindowManager`:

```swift
private let accessLogger: PrivacyPulseAccessLogging

init(accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()) {
    self.accessLogger = accessLogger
}
```

At the start of `perform(_:)`, record:

```swift
accessLogger.record(
    category: .accessibility,
    title: "Accessibility Window Action",
    detail: action.title
)
```

Keep the existing `WindowManaging` protocol unchanged so command palette providers and tests remain compatible.

- [ ] **Step 3: Log Accessibility hotkey trust checks**

In `platforms/macos/Atlas/GlobalHotkeyService.swift`, add:

```swift
private let accessLogger: PrivacyPulseAccessLogging

init(accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()) {
    self.accessLogger = accessLogger
}
```

At the beginning of `requestAccessibilityIfNeeded()`, record:

```swift
accessLogger.record(
    category: .accessibility,
    title: "Accessibility Check",
    detail: "Global hotkey trust checked"
)
```

Do not change tests to call real Accessibility prompts.

- [ ] **Step 4: Add injected logging tests**

In service tests, use the fake logger from Task 5 or a shared local fake:

```swift
func testCaptureDesktopLogsScreenRecordingAccess() throws {
    let bridge = FakeAtlasCaptureBridge()
    let logger = FakePrivacyPulseAccessLogger()
    let service = AtlasCaptureService(bridge: bridge, accessLogger: logger)

    _ = try service.captureDesktop()

    XCTAssertTrue(logger.records.contains { record in
        record.0 == .screenRecording && record.1 == "Screen Capture"
    })
}
```

For window management, test an injected or fake `WindowManaging` boundary if the current `AccessibilityWindowManager` cannot be exercised without real Accessibility APIs. Do not create real windows or require Accessibility permission. If `AccessibilityWindowManager.perform(_:)` is the only concrete boundary, add a narrow logger test around a lightweight wrapper that records before delegating:

```swift
final class LoggingWindowManager: WindowManaging {
    private let wrapped: WindowManaging
    private let accessLogger: PrivacyPulseAccessLogging

    init(wrapped: WindowManaging, accessLogger: PrivacyPulseAccessLogging) {
        self.wrapped = wrapped
        self.accessLogger = accessLogger
    }

    @discardableResult
    func perform(_ action: WindowManagementAction) -> Bool {
        accessLogger.record(
            category: .accessibility,
            title: "Accessibility Window Action",
            detail: action.title
        )
        return wrapped.perform(action)
    }
}
```

Then test with a fake wrapped manager:

```swift
func testLoggingWindowManagerRecordsAccessibilityActionWithoutRealAX() {
    let wrapped = FakeWindowManager(result: true)
    let logger = FakePrivacyPulseAccessLogger()
    let manager = LoggingWindowManager(wrapped: wrapped, accessLogger: logger)

    XCTAssertTrue(manager.perform(.leftHalf))

    XCTAssertEqual(logger.records.first?.0, .accessibility)
    XCTAssertEqual(logger.records.first?.1, "Accessibility Window Action")
    XCTAssertEqual(wrapped.actions, [.leftHalf])
}
```

- [ ] **Step 5: Verify capture and Accessibility tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/AtlasCaptureServiceTests -only-testing:AtlasTests/WindowManagementServiceTests -only-testing:AtlasTests/GlobalHotkeyServiceTests
```

Expected: Tests pass. They use injected bridge/window manager/logger fakes and do not require Screen Recording or Accessibility permission.

- [ ] **Step 6: Commit screen and Accessibility logging**

Run:

```bash
git add platforms/macos/Atlas/AtlasCaptureService.swift platforms/macos/Atlas/WindowManagementService.swift platforms/macos/Atlas/GlobalHotkeyService.swift platforms/macos/AtlasTests/AtlasCaptureServiceTests.swift platforms/macos/AtlasTests/WindowManagementServiceTests.swift platforms/macos/AtlasTests/GlobalHotkeyServiceTests.swift
git commit -m "feat: log Atlas screen and Accessibility access"
```

Expected: The commit contains only screen capture and Accessibility logging plus injected-boundary tests.

---

### Task 7: Wire Shared Logger Through App Composition

**Files:**
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Modify: `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift`

- [ ] **Step 1: Own one shared logger and service in AtlasApp**

In `platforms/macos/Atlas/AtlasApp.swift`, add shared app-level objects:

```swift
@StateObject private var paletteState = CommandPaletteState()
private let privacyAccessLogger = PrivacyPulseAccessLogger()
private let privacyStatusProvider = PrivacyPulseSystemStatusProvider()
```

Pass the service to `ContentView`:

```swift
ContentView(
    paletteState: paletteState,
    privacyPulseService: PrivacyPulseService(
        statusProvider: privacyStatusProvider,
        eventStore: privacyAccessLogger
    )
)
```

If SwiftUI rejects stored non-state properties in `App`, move object construction into a small `AtlasAppServices` reference type:

```swift
final class AtlasAppServices {
    let privacyAccessLogger = PrivacyPulseAccessLogger()
    let privacyStatusProvider = PrivacyPulseSystemStatusProvider()

    var privacyPulseService: PrivacyPulseService {
        PrivacyPulseService(
            statusProvider: privacyStatusProvider,
            eventStore: privacyAccessLogger
        )
    }
}
```

Use one `private let services = AtlasAppServices()` and pass `services.privacyPulseService`.

- [ ] **Step 2: Pass logger to command providers additively**

Update `CommandPaletteState` so it accepts a logger:

```swift
private let accessLogger: PrivacyPulseAccessLogging

init(accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()) {
    self.accessLogger = accessLogger
    let atlasProvider = AtlasCommandProvider(
        onCaptureDesktop: { [weak self] in self?.onCaptureDesktop?() },
        onCaptureArea: { [weak self] in self?.onCaptureArea?() },
        onCaptureWindow: { [weak self] in self?.onCaptureWindow?() },
        onOpenSettings: {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    )
    let developerToolsProvider = DeveloperToolsProvider()
    let windowManagementProvider = WindowManagementProvider(
        windowManager: AccessibilityWindowManager(accessLogger: accessLogger)
    )
    let clipboardHistoryProvider = ClipboardHistoryProvider(accessLogger: accessLogger)
    let snippetsProvider = SnippetsProvider(accessLogger: accessLogger)
    let appLauncherProvider = AppLauncherProvider()

    self.controller = CommandPaletteController(providers: [
        atlasProvider,
        developerToolsProvider,
        windowManagementProvider,
        clipboardHistoryProvider,
        snippetsProvider,
        appLauncherProvider,
    ])

    self.controller.onHotkeyChanged = { [weak self] newConfig in
        self?.registerHotkey(newConfig)
    }

    let config = HotkeyConfig.load()
    registerHotkey(config)
    hotkeyService.start()
}
```

Preserve provider order and any adjacent child-plan providers already inserted by other tasks. Add logger arguments only to providers that support them.

- [ ] **Step 3: Pass logger to hotkey service and capture service boundaries**

In `ContentView`, replace local default hotkey construction with injected or logger-backed construction:

```swift
private let hotkeyService: GlobalHotkeyService

init(
    paletteState: CommandPaletteState? = nil,
    privacyPulseService: PrivacyPulseService? = nil,
    accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
) {
    self.paletteState = paletteState
    self.privacyPulseService = privacyPulseService
    self.hotkeyService = GlobalHotkeyService(accessLogger: accessLogger)
}
```

If `ContentView` already has a custom initializer from another child plan, add `privacyPulseService` and `accessLogger` parameters to that initializer and keep the existing arguments intact.

- [ ] **Step 4: Verify app composition**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: The app builds. There is one shared Privacy Pulse logger wired into command providers, hotkey checks, and the Privacy Pulse panel service.

- [ ] **Step 5: Commit app composition**

Run:

```bash
git add platforms/macos/Atlas/AtlasApp.swift platforms/macos/Atlas/ContentView.swift platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift
git commit -m "feat: wire Privacy Pulse logging"
```

Expected: The commit contains only app composition changes.

---

### Task 8: Final Verification and Project Membership Audit

**Files:**
- Verify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
- Verify: all Privacy Pulse app and test files

- [ ] **Step 1: Verify all new files have PBX membership**

Run:

```bash
rg -n 'PrivacyPulseModels|PrivacyPulseAccessLogger|PrivacyPulseSystemStatusProvider|PrivacyPulseService|PrivacyPulsePanel|PrivacyPulseServiceTests|PrivacyPulsePanelTests' platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: Each new Swift app file appears as a file reference and in the Atlas sources build phase. Each new Swift test file appears as a file reference and in the AtlasTests sources build phase.

- [ ] **Step 2: Run focused Privacy Pulse tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/PrivacyPulseServiceTests -only-testing:AtlasTests/PrivacyPulsePanelTests
```

Expected: Privacy Pulse tests pass using injected status providers, injected event stores, and in-memory loggers.

- [ ] **Step 3: Run privacy-adjacent regression tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/ClipboardHistoryProviderTests -only-testing:AtlasTests/SnippetsProviderTests -only-testing:AtlasTests/ScreenshotOutputTests -only-testing:AtlasTests/AtlasCaptureServiceTests -only-testing:AtlasTests/WindowManagementServiceTests -only-testing:AtlasTests/GlobalHotkeyServiceTests -only-testing:AtlasTests/FeatureModelsTests
```

Expected: Clipboard, screenshot output, capture service, window management, hotkey, and feature model tests pass. None of the tests open real camera/microphone sessions, read uncontrolled real clipboard contents, or change real permissions.

- [ ] **Step 4: Run Rust feature test**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
```

Expected: The feature list test passes and includes `privacy`.

- [ ] **Step 5: Build the macOS app**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: The app builds with all new Swift files included in explicit project membership.

- [ ] **Step 6: Review diff for scope**

Run:

```bash
git diff --stat HEAD
git diff -- crates/atlas-core/src/features.rs platforms/macos/Atlas platforms/macos/AtlasTests platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: The diff is limited to Privacy Pulse feature gating, models, service, panel, Atlas-internal privacy access logging, tests, and PBX membership. It does not contain unrelated refactors or production code for detecting other apps' privacy usage.

- [ ] **Step 7: Commit verification note if needed**

If verification documentation is updated, run:

```bash
git add docs/superpowers/plans/2026-05-22-privacy-pulse-v1.md
git commit -m "docs: record Privacy Pulse verification"
```

Expected: The commit contains only verification notes in this plan.

## Acceptance Criteria

- `privacy` appears in Feature Center as `Privacy Pulse` and defaults disabled.
- When `privacy` is disabled, the Privacy Pulse panel is not shown.
- When `privacy` is enabled, the panel shows visible statuses for camera, microphone, clipboard reads, screen recording, and Accessibility use.
- Camera and microphone status use authorization-status reads only; Privacy Pulse does not open capture sessions.
- Screen Recording status uses public preflight status only; tests do not request permission.
- Accessibility status uses public trust status only; tests do not request or require permission.
- Atlas clipboard reads/writes, screenshot screen capture attempts, screen recording checks, and Accessibility actions/checks are recorded in the Atlas-internal event log.
- Tests use injected fake status providers, fake event stores, fake loggers, fake clipboard readers, and fake capture/window boundaries.
- The Xcode project includes every new Swift app and test file in explicit PBX project membership.

## Self-Review

1. **Spec coverage:** Visible camera, microphone, clipboard reads, screen recording, and Accessibility status are implemented by Task 3 and Task 4. Atlas-internal logging is implemented by Task 2, Task 5, Task 6, and Task 7. Feature Center gating is implemented by Task 1 and Task 4. Injected event-source tests are implemented by Task 2, Task 3, Task 5, Task 6, and Task 8.
2. **Placeholder scan:** This plan contains concrete file paths, code snippets, commands, and expected results. It intentionally avoids production global monitoring for other apps because v1 uses public APIs and Atlas-internal logging only.
3. **Type consistency:** `PrivacyPulseCategory`, `PrivacyPulseStatus`, `PrivacyPulseEvent`, `PrivacyPulseSnapshot`, `PrivacyPulseAccessLogging`, `PrivacyPulseEventStoring`, `PrivacyPulseStatusProviding`, and `PrivacyPulseService` signatures are defined before later tasks use them.
