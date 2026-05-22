# System Utilities v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add gated system utility modules for keep-awake, presentation mode, hand mirror, and display capability detection.

**Architecture:** Keep v1 in Swift. System operations run behind injected adapters so tests never call `caffeinate`, `osascript`, camera APIs, or DDC tools directly. Keep-awake owns a long-lived cancellable command process. Presentation mode composes keep-awake plus notification-focus commands. Hand mirror uses AVFoundation permission state and a local SwiftUI preview panel. Display control v1 detects DDC/CI capability and external-display brightness support, but does not change brightness unless capability is explicitly detected.

**Tech Stack:** Swift, SwiftUI, AVFoundation, Foundation `Process`, XCTest, Rust Feature Center registry, UniFFI feature list/toggle bridge, explicit Xcode PBX project membership.

---

## Scope

This plan implements:

- Keep-awake start/stop backed by `caffeinate -dimsu`.
- Presentation mode start/stop that keeps the Mac awake and mutes notifications through injected command adapters.
- Hand mirror camera permission handling and preview panel wiring.
- Display capability detection for DDC/CI and external brightness support.
- Feature Center gating for all system utilities UI and command palette commands.
- Deterministic tests using injected system command adapters, camera permission providers, and display capability probes.

Out of scope:

- Production DDC brightness writes.
- Private macOS display APIs.
- Screen dimming or wallpaper changes.
- Persisted schedules.
- Camera recording, snapshots, or network streaming.
- Rust or UniFFI APIs beyond registering the `system-utilities` feature name.

## Current Baseline

The required audit command:

```bash
rg -n 'awake|caffeinate|presentation|camera|mirror|display|brightness|DDC|mute notifications' platforms/macos/Atlas platforms/macos/AtlasTests docs/superpowers/plans
```

shows screenshot/display references, command palette icon fixtures, and roadmap/planning text. It does not show current production implementations for keep-awake, presentation mode, hand mirror, DDC/CI display capability detection, or notification muting.

## File Map

**New files:**

- `platforms/macos/Atlas/SystemUtilitiesModels.swift`
  - Defines shared state, permission, display, and command-result models.
- `platforms/macos/Atlas/SystemCommandRunner.swift`
  - Defines `SystemCommandRunning`, `SystemCommandProcess`, and live `Process` adapters.
- `platforms/macos/Atlas/KeepAwakeService.swift`
  - Starts and stops the injected keep-awake command process.
- `platforms/macos/Atlas/PresentationModeService.swift`
  - Composes keep-awake and notification mute/unmute commands.
- `platforms/macos/Atlas/HandMirrorService.swift`
  - Wraps injected camera permission state/request behavior.
- `platforms/macos/Atlas/CameraPreviewPanel.swift`
  - SwiftUI hand mirror panel and live preview wrapper.
- `platforms/macos/Atlas/DisplayControlService.swift`
  - Detects displays and DDC/CI capability through injected probes.
- `platforms/macos/Atlas/SystemUtilitiesPanel.swift`
  - SwiftUI controls for the utilities.
- `platforms/macos/Atlas/CommandPalette/SystemUtilitiesProvider.swift`
  - Command palette entries for keep-awake, presentation mode, hand mirror, and display status.
- `platforms/macos/AtlasTests/KeepAwakeServiceTests.swift`
- `platforms/macos/AtlasTests/PresentationModeServiceTests.swift`
- `platforms/macos/AtlasTests/HandMirrorServiceTests.swift`
- `platforms/macos/AtlasTests/DisplayControlServiceTests.swift`
- `platforms/macos/AtlasTests/SystemUtilitiesProviderTests.swift`
- `platforms/macos/AtlasTests/SystemUtilitiesPanelTests.swift`

**Modified files:**

- `crates/atlas-core/src/features.rs`
  - Registers `system-utilities` disabled by default.
- `platforms/macos/Atlas/AtlasModule.swift`
  - Adds `case systemUtilities = "system-utilities"` additively.
- `platforms/macos/Atlas/FeatureModels.swift`
  - Maps `system-utilities` to `System Utilities`.
- `platforms/macos/Atlas/ContentView.swift`
  - Shows `SystemUtilitiesPanel` only when enabled.
- `platforms/macos/Atlas/AtlasApp.swift`
  - Creates services and adds the command palette provider additively.
- `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`
  - Adds a hand mirror destination additively if a pushed preview destination is used.
- `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`
  - Adds optional hand mirror builder additively if a pushed preview destination is used.
- `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`
  - Renders the pushed hand mirror destination additively if used.
- `platforms/macos/AtlasTests/FeatureModelsTests.swift`
  - Adds System Utilities title coverage.
- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds every new Swift app file to the `Atlas` target sources and every new Swift test file to the `AtlasTests` target sources.

Project membership rule: this repo uses explicit PBX project references. Every new Swift file listed above must appear as a `PBXFileReference`, a `PBXBuildFile`, in the correct group, and in the correct `PBXSourcesBuildPhase` before running `xcodebuild test`.

---

## Task 1: Register Feature Center Gate

**Files:**
- Modify: `crates/atlas-core/src/features.rs`
- Modify: `platforms/macos/Atlas/AtlasModule.swift`
- Modify: `platforms/macos/Atlas/FeatureModels.swift`
- Test: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

- [ ] **Step 1: Add the Rust feature name**

In `crates/atlas-core/src/features.rs`, add `system-utilities` to the existing registrations in `FeatureManager::new()`:

```rust
features.insert("system-utilities".to_string(), FeatureStatus::Disabled);
```

Do not replace the existing feature set with a closed list. Insert only this registration, preserving names added by adjacent child plans such as `scratchpad`, `tokenbar`, `ai-load-monitor`, `window-manager`, or later features.

Update the feature list test additively:

```rust
#[test]
fn test_list_features_is_sorted_by_name() {
    let fm = FeatureManager::new();
    let names: Vec<_> = fm.list_features().into_iter().map(|(name, _)| name).collect();

    assert!(names.contains(&"system-utilities".to_string()));
    assert!(names.windows(2).all(|pair| pair[0] <= pair[1]));
}
```

- [ ] **Step 2: Add the Swift module case additively**

In `platforms/macos/Atlas/AtlasModule.swift`, add the case and title branch without removing adjacent child-plan cases:

```swift
enum AtlasModule: String, CaseIterable, Identifiable {
    case screenshot
    case monitoring
    case systemUtilities = "system-utilities"
    // Preserve any existing cases already in this file.

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
        case .systemUtilities:
            return "System Utilities"
        // Preserve switch branches for any existing cases already in this file.
        }
    }
}
```

- [ ] **Step 3: Add feature title mapping**

In `platforms/macos/Atlas/FeatureModels.swift`, add this switch branch:

```swift
case AtlasModule.systemUtilities.featureName:
    return AtlasModule.systemUtilities.title
```

Add this test to `platforms/macos/AtlasTests/FeatureModelsTests.swift`:

```swift
func testMapsSystemUtilitiesTitle() {
    let feature = AtlasFeature(name: "system-utilities", isEnabled: false)

    XCTAssertEqual(feature.title, "System Utilities")
}
```

- [ ] **Step 4: Verify the gate**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureModelsTests
```

Expected: Rust feature ordering and Swift title tests pass.

---

## Task 2: Add Shared Models and Command Adapter

**Files:**
- Create: `platforms/macos/Atlas/SystemUtilitiesModels.swift`
- Create: `platforms/macos/Atlas/SystemCommandRunner.swift`
- Test: compile through later service tests

- [ ] **Step 1: Add shared models**

Create `platforms/macos/Atlas/SystemUtilitiesModels.swift`:

```swift
import Foundation

enum SystemUtilityStatus: Equatable {
    case idle
    case running
    case unavailable(String)
    case failed(String)
}

struct SystemCommandResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool {
        terminationStatus == 0
    }
}

enum CameraPermissionState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

struct DisplayDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let isBuiltin: Bool
    let supportsDDC: Bool
    let supportsSoftwareBrightness: Bool

    var capabilitySummary: String {
        if supportsDDC {
            return "DDC/CI available"
        }
        if supportsSoftwareBrightness {
            return "Software brightness available"
        }
        return "Brightness control unavailable"
    }
}

struct SystemUtilitiesState: Equatable {
    var keepAwake: SystemUtilityStatus
    var presentationMode: SystemUtilityStatus
    var cameraPermission: CameraPermissionState
    var displays: [DisplayDevice]

    static let initial = SystemUtilitiesState(
        keepAwake: .idle,
        presentationMode: .idle,
        cameraPermission: .notDetermined,
        displays: []
    )
}
```

- [ ] **Step 2: Add injected command runner**

Create `platforms/macos/Atlas/SystemCommandRunner.swift`:

```swift
import Foundation

protocol SystemCommandProcess: AnyObject {
    var isRunning: Bool { get }
    func terminate()
}

protocol SystemCommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult
    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess
}

enum SystemCommandRunnerError: Error, Equatable {
    case invalidOutput
}

final class LiveSystemCommandProcess: SystemCommandProcess {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        process.terminate()
    }
}

struct LiveSystemCommandRunner: SystemCommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        return SystemCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            standardError: String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        return LiveSystemCommandProcess(process: process)
    }
}
```

---

## Task 3: Implement Keep-Awake Service

**Files:**
- Create: `platforms/macos/Atlas/KeepAwakeService.swift`
- Create: `platforms/macos/AtlasTests/KeepAwakeServiceTests.swift`

- [ ] **Step 1: Add tests first**

Create `platforms/macos/AtlasTests/KeepAwakeServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class KeepAwakeServiceTests: XCTestCase {
    func testStartLaunchesCaffeinateOnce() throws {
        let runner = FakeSystemCommandRunner()
        let service = KeepAwakeService(commandRunner: runner)

        try service.start()
        try service.start()

        XCTAssertEqual(runner.startedCommands, [
            FakeSystemCommandRunner.StartedCommand(executable: "/usr/bin/caffeinate", arguments: ["-dimsu"])
        ])
        XCTAssertEqual(service.status, .running)
    }

    func testStopTerminatesRunningProcess() throws {
        let runner = FakeSystemCommandRunner()
        let service = KeepAwakeService(commandRunner: runner)

        try service.start()
        service.stop()

        XCTAssertEqual(runner.processes.first?.terminateCallCount, 1)
        XCTAssertEqual(service.status, .idle)
    }

    func testStartFailureSetsFailedStatus() {
        let runner = FakeSystemCommandRunner(startError: NSError(domain: "test", code: 1))
        let service = KeepAwakeService(commandRunner: runner)

        XCTAssertThrowsError(try service.start())
        XCTAssertEqual(service.status, .failed("The operation couldn't be completed. (test error 1.)"))
    }
}

final class FakeSystemCommandProcess: SystemCommandProcess {
    var isRunning = true
    private(set) var terminateCallCount = 0

    func terminate() {
        terminateCallCount += 1
        isRunning = false
    }
}

final class FakeSystemCommandRunner: SystemCommandRunning {
    struct StartedCommand: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let startError: Error?
    private(set) var startedCommands: [StartedCommand] = []
    private(set) var processes: [FakeSystemCommandProcess] = []

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        SystemCommandResult(terminationStatus: 0, standardOutput: "", standardError: "")
    }

    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
        if let startError {
            throw startError
        }
        startedCommands.append(StartedCommand(executable: executable, arguments: arguments))
        let process = FakeSystemCommandProcess()
        processes.append(process)
        return process
    }
}
```

- [ ] **Step 2: Add service**

Create `platforms/macos/Atlas/KeepAwakeService.swift`:

```swift
import Foundation

final class KeepAwakeService: ObservableObject {
    @Published private(set) var status: SystemUtilityStatus = .idle

    private let commandRunner: SystemCommandRunning
    private var process: SystemCommandProcess?

    init(commandRunner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func start() throws {
        if process?.isRunning == true {
            status = .running
            return
        }

        do {
            process = try commandRunner.start("/usr/bin/caffeinate", arguments: ["-dimsu"])
            status = .running
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        status = .idle
    }
}
```

- [ ] **Step 3: Verify keep-awake tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/KeepAwakeServiceTests
```

Expected: tests pass without launching real `caffeinate`.

---

## Task 4: Implement Presentation Mode Service

**Files:**
- Create: `platforms/macos/Atlas/PresentationModeService.swift`
- Create: `platforms/macos/AtlasTests/PresentationModeServiceTests.swift`

- [ ] **Step 1: Add tests**

Create `platforms/macos/AtlasTests/PresentationModeServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class PresentationModeServiceTests: XCTestCase {
    func testStartKeepsAwakeAndMutesNotifications() throws {
        let runner = RecordingCommandRunner()
        let keepAwake = KeepAwakeService(commandRunner: runner)
        let service = PresentationModeService(commandRunner: runner, keepAwakeService: keepAwake)

        try service.start()

        XCTAssertEqual(runner.startedCommands, [
            RecordingCommandRunner.Command(executable: "/usr/bin/caffeinate", arguments: ["-dimsu"])
        ])
        XCTAssertEqual(runner.ranCommands, [
            RecordingCommandRunner.Command(executable: "/usr/bin/osascript", arguments: [
                "-e",
                "tell application \"System Events\" to tell process \"Control Center\" to key code 113 using {option down}"
            ])
        ])
        XCTAssertEqual(service.status, .running)
    }

    func testStopUnmutesNotificationsAndStopsKeepAwake() throws {
        let runner = RecordingCommandRunner()
        let keepAwake = KeepAwakeService(commandRunner: runner)
        let service = PresentationModeService(commandRunner: runner, keepAwakeService: keepAwake)

        try service.start()
        service.stop()

        XCTAssertEqual(runner.processes.first?.terminateCallCount, 1)
        XCTAssertEqual(runner.ranCommands.last, RecordingCommandRunner.Command(executable: "/usr/bin/osascript", arguments: [
            "-e",
            "tell application \"System Events\" to tell process \"Control Center\" to key code 113 using {option down}"
        ]))
        XCTAssertEqual(service.status, .idle)
    }

    func testNotificationCommandFailureReportsUnavailable() {
        let runner = RecordingCommandRunner(runResult: SystemCommandResult(terminationStatus: 1, standardOutput: "", standardError: "not allowed"))
        let service = PresentationModeService(commandRunner: runner, keepAwakeService: KeepAwakeService(commandRunner: runner))

        XCTAssertThrowsError(try service.start())
        XCTAssertEqual(service.status, .failed("not allowed"))
    }
}

final class RecordingCommandRunner: SystemCommandRunning {
    struct Command: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let runResult: SystemCommandResult
    private(set) var ranCommands: [Command] = []
    private(set) var startedCommands: [Command] = []
    private(set) var processes: [FakeSystemCommandProcess] = []

    init(runResult: SystemCommandResult = SystemCommandResult(terminationStatus: 0, standardOutput: "", standardError: "")) {
        self.runResult = runResult
    }

    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        ranCommands.append(Command(executable: executable, arguments: arguments))
        return runResult
    }

    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
        startedCommands.append(Command(executable: executable, arguments: arguments))
        let process = FakeSystemCommandProcess()
        processes.append(process)
        return process
    }
}
```

- [ ] **Step 2: Add service**

Create `platforms/macos/Atlas/PresentationModeService.swift`:

```swift
import Foundation

final class PresentationModeService: ObservableObject {
    @Published private(set) var status: SystemUtilityStatus = .idle

    private let commandRunner: SystemCommandRunning
    private let keepAwakeService: KeepAwakeService
    private let muteNotificationsScript = "tell application \"System Events\" to tell process \"Control Center\" to key code 113 using {option down}"

    init(
        commandRunner: SystemCommandRunning = LiveSystemCommandRunner(),
        keepAwakeService: KeepAwakeService
    ) {
        self.commandRunner = commandRunner
        self.keepAwakeService = keepAwakeService
    }

    func start() throws {
        do {
            try keepAwakeService.start()
            let result = try commandRunner.run("/usr/bin/osascript", arguments: ["-e", muteNotificationsScript])
            guard result.succeeded else {
                let message = result.standardError.isEmpty ? "Unable to mute notifications" : result.standardError
                status = .failed(message)
                throw PresentationModeError.commandFailed(message)
            }
            status = .running
        } catch {
            if case .failed = status {
            } else {
                status = .failed(error.localizedDescription)
            }
            throw error
        }
    }

    func stop() {
        _ = try? commandRunner.run("/usr/bin/osascript", arguments: ["-e", muteNotificationsScript])
        keepAwakeService.stop()
        status = .idle
    }
}

enum PresentationModeError: Error, Equatable {
    case commandFailed(String)
}
```

Permission behavior: if Automation permission blocks `osascript`, show the failure message in the panel and leave keep-awake stopped by calling `keepAwakeService.stop()` before throwing. If the implementation chooses to keep awake despite notification failure, it must say so in UI text and tests. Prefer stopping to avoid partially enabled presentation mode.

- [ ] **Step 3: Verify presentation tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/PresentationModeServiceTests
```

Expected: presentation behavior is verified through injected command results only.

---

## Task 5: Implement Hand Mirror Permission and Preview

**Files:**
- Create: `platforms/macos/Atlas/HandMirrorService.swift`
- Create: `platforms/macos/Atlas/CameraPreviewPanel.swift`
- Create: `platforms/macos/AtlasTests/HandMirrorServiceTests.swift`

- [ ] **Step 1: Add camera permission tests**

Create `platforms/macos/AtlasTests/HandMirrorServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class HandMirrorServiceTests: XCTestCase {
    func testAuthorizedPermissionCanOpenMirror() async {
        let permissions = FakeCameraPermissionProvider(state: .authorized)
        let service = HandMirrorService(permissionProvider: permissions)

        let allowed = await service.prepareForPreview()

        XCTAssertTrue(allowed)
        XCTAssertEqual(service.permissionState, .authorized)
    }

    func testDeniedPermissionDoesNotOpenMirror() async {
        let permissions = FakeCameraPermissionProvider(state: .denied)
        let service = HandMirrorService(permissionProvider: permissions)

        let allowed = await service.prepareForPreview()

        XCTAssertFalse(allowed)
        XCTAssertEqual(service.permissionState, .denied)
    }

    func testNotDeterminedRequestsPermission() async {
        let permissions = FakeCameraPermissionProvider(state: .notDetermined, requestResult: true)
        let service = HandMirrorService(permissionProvider: permissions)

        let allowed = await service.prepareForPreview()

        XCTAssertTrue(allowed)
        XCTAssertEqual(permissions.requestCallCount, 1)
        XCTAssertEqual(service.permissionState, .authorized)
    }
}

final class FakeCameraPermissionProvider: CameraPermissionProviding {
    private var state: CameraPermissionState
    private let requestResult: Bool
    private(set) var requestCallCount = 0

    init(state: CameraPermissionState, requestResult: Bool = false) {
        self.state = state
        self.requestResult = requestResult
    }

    func currentState() -> CameraPermissionState {
        state
    }

    func requestAccess() async -> Bool {
        requestCallCount += 1
        state = requestResult ? .authorized : .denied
        return requestResult
    }
}
```

- [ ] **Step 2: Add hand mirror service**

Create `platforms/macos/Atlas/HandMirrorService.swift`:

```swift
import AVFoundation
import Foundation

protocol CameraPermissionProviding {
    func currentState() -> CameraPermissionState
    func requestAccess() async -> Bool
}

struct LiveCameraPermissionProvider: CameraPermissionProviding {
    func currentState() -> CameraPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

@MainActor
final class HandMirrorService: ObservableObject {
    @Published private(set) var permissionState: CameraPermissionState

    private let permissionProvider: CameraPermissionProviding

    init(permissionProvider: CameraPermissionProviding = LiveCameraPermissionProvider()) {
        self.permissionProvider = permissionProvider
        self.permissionState = permissionProvider.currentState()
    }

    func prepareForPreview() async -> Bool {
        permissionState = permissionProvider.currentState()

        switch permissionState {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await permissionProvider.requestAccess()
            permissionState = granted ? .authorized : .denied
            return granted
        case .denied, .restricted:
            return false
        }
    }
}
```

- [ ] **Step 3: Add preview panel**

Create `platforms/macos/Atlas/CameraPreviewPanel.swift`:

```swift
import AVFoundation
import SwiftUI

struct CameraPreviewPanel: View {
    let permissionState: CameraPermissionState
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hand Mirror")
                .font(.headline)

            switch permissionState {
            case .authorized:
                LiveCameraPreview()
                    .frame(width: 320, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            case .notDetermined:
                Button("Enable Camera", action: onRequestAccess)
            case .denied:
                Text("Camera access is denied in System Settings.")
                    .foregroundStyle(.secondary)
            case .restricted:
                Text("Camera access is restricted on this Mac.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LiveCameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        Task.detached {
            session.startRunning()
        }
        context.coordinator.session = session
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.frame = nsView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var session: AVCaptureSession?

        deinit {
            session?.stopRunning()
        }
    }
}
```

Permission behavior: the UI must never start `AVCaptureSession` unless `CameraPermissionState.authorized` is known. Denied and restricted states show status text only.

- [ ] **Step 4: Verify hand mirror tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/HandMirrorServiceTests
```

Expected: permission behavior is tested without accessing real camera hardware.

---

## Task 6: Implement Display DDC/CI Capability Detection

**Files:**
- Create: `platforms/macos/Atlas/DisplayControlService.swift`
- Create: `platforms/macos/AtlasTests/DisplayControlServiceTests.swift`

- [ ] **Step 1: Add display capability tests**

Create `platforms/macos/AtlasTests/DisplayControlServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class DisplayControlServiceTests: XCTestCase {
    func testDetectsDDCSupportFromProbeOutput() throws {
        let probe = FakeDisplayCapabilityProbe(result: SystemCommandResult(
            terminationStatus: 0,
            standardOutput: "Display 1: Built-in Retina\nDisplay 2: LG UltraFine DDC/CI supported\n",
            standardError: ""
        ))
        let service = DisplayControlService(probe: probe)

        let displays = try service.refreshDisplays()

        XCTAssertEqual(displays, [
            DisplayDevice(id: "display-1", name: "Built-in Retina", isBuiltin: true, supportsDDC: false, supportsSoftwareBrightness: true),
            DisplayDevice(id: "display-2", name: "LG UltraFine", isBuiltin: false, supportsDDC: true, supportsSoftwareBrightness: false),
        ])
    }

    func testUnavailableProbeReturnsEmptyList() {
        let probe = FakeDisplayCapabilityProbe(result: SystemCommandResult(
            terminationStatus: 127,
            standardOutput: "",
            standardError: "ddcctl not found"
        ))
        let service = DisplayControlService(probe: probe)

        XCTAssertThrowsError(try service.refreshDisplays())
        XCTAssertEqual(service.displays, [])
        XCTAssertEqual(service.status, .unavailable("ddcctl not found"))
    }
}

struct FakeDisplayCapabilityProbe: DisplayCapabilityProbing {
    let result: SystemCommandResult

    func probe() throws -> SystemCommandResult {
        result
    }
}
```

- [ ] **Step 2: Add display service**

Create `platforms/macos/Atlas/DisplayControlService.swift`:

```swift
import Foundation

protocol DisplayCapabilityProbing {
    func probe() throws -> SystemCommandResult
}

struct LiveDisplayCapabilityProbe: DisplayCapabilityProbing {
    private let commandRunner: SystemCommandRunning

    init(commandRunner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func probe() throws -> SystemCommandResult {
        try commandRunner.run("/usr/bin/env", arguments: ["ddcctl", "-d", "1", "-b", "?"])
    }
}

final class DisplayControlService: ObservableObject {
    @Published private(set) var displays: [DisplayDevice] = []
    @Published private(set) var status: SystemUtilityStatus = .idle

    private let probe: DisplayCapabilityProbing

    init(probe: DisplayCapabilityProbing = LiveDisplayCapabilityProbe()) {
        self.probe = probe
    }

    @discardableResult
    func refreshDisplays() throws -> [DisplayDevice] {
        let result = try probe.probe()
        guard result.succeeded else {
            let message = result.standardError.isEmpty ? "Display control probe failed" : result.standardError
            displays = []
            status = .unavailable(message)
            throw DisplayControlError.probeFailed(message)
        }

        displays = DisplayControlParser.parse(result.standardOutput)
        status = displays.isEmpty ? .unavailable("No controllable displays detected") : .idle
        return displays
    }
}

enum DisplayControlError: Error, Equatable {
    case probeFailed(String)
}

enum DisplayControlParser {
    static func parse(_ output: String) -> [DisplayDevice] {
        output
            .split(separator: "\n")
            .enumerated()
            .compactMap { index, line in
                let text = String(line)
                guard text.hasPrefix("Display ") else {
                    return nil
                }

                let components = text.split(separator: ":", maxSplits: 1).map(String.init)
                guard components.count == 2 else {
                    return nil
                }

                let rawName = components[1]
                    .replacingOccurrences(of: "DDC/CI supported", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let isBuiltin = rawName.localizedCaseInsensitiveContains("built-in")
                let supportsDDC = text.localizedCaseInsensitiveContains("DDC/CI supported")

                return DisplayDevice(
                    id: "display-\(index + 1)",
                    name: rawName,
                    isBuiltin: isBuiltin,
                    supportsDDC: supportsDDC,
                    supportsSoftwareBrightness: isBuiltin
                )
            }
    }
}
```

Capability behavior: v1 detects and reports DDC/CI availability only. Do not implement brightness writes in this plan unless the user explicitly requests a follow-up implementation plan for brightness control.

- [ ] **Step 3: Verify display tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/DisplayControlServiceTests
```

Expected: tests pass without requiring external displays or `ddcctl`.

---

## Task 7: Add System Utilities Panel and App Wiring

**Files:**
- Create: `platforms/macos/Atlas/SystemUtilitiesPanel.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Create: `platforms/macos/AtlasTests/SystemUtilitiesPanelTests.swift`

- [ ] **Step 1: Add panel tests**

Create `platforms/macos/AtlasTests/SystemUtilitiesPanelTests.swift`:

```swift
import XCTest
@testable import Atlas

final class SystemUtilitiesPanelTests: XCTestCase {
    func testPanelActionsAreCallable() {
        var keepAwakeStartCount = 0
        var presentationStartCount = 0
        var mirrorOpenCount = 0
        var refreshCount = 0

        let model = SystemUtilitiesPanelModel(
            state: .initial,
            onToggleKeepAwake: { keepAwakeStartCount += 1 },
            onTogglePresentationMode: { presentationStartCount += 1 },
            onOpenHandMirror: { mirrorOpenCount += 1 },
            onRefreshDisplays: { refreshCount += 1 }
        )

        model.onToggleKeepAwake()
        model.onTogglePresentationMode()
        model.onOpenHandMirror()
        model.onRefreshDisplays()

        XCTAssertEqual(keepAwakeStartCount, 1)
        XCTAssertEqual(presentationStartCount, 1)
        XCTAssertEqual(mirrorOpenCount, 1)
        XCTAssertEqual(refreshCount, 1)
    }
}
```

- [ ] **Step 2: Add panel**

Create `platforms/macos/Atlas/SystemUtilitiesPanel.swift`:

```swift
import SwiftUI

struct SystemUtilitiesPanelModel {
    let state: SystemUtilitiesState
    let onToggleKeepAwake: () -> Void
    let onTogglePresentationMode: () -> Void
    let onOpenHandMirror: () -> Void
    let onRefreshDisplays: () -> Void
}

struct SystemUtilitiesPanel: View {
    let model: SystemUtilitiesPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Utilities")
                .font(.headline)

            HStack {
                Button(keepAwakeTitle, action: model.onToggleKeepAwake)
                Button(presentationTitle, action: model.onTogglePresentationMode)
                Button("Hand Mirror", action: model.onOpenHandMirror)
                Button("Refresh Displays", action: model.onRefreshDisplays)
            }

            if !model.state.displays.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.state.displays) { display in
                        HStack {
                            Text(display.name)
                            Spacer()
                            Text(display.capabilitySummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var keepAwakeTitle: String {
        model.state.keepAwake == .running ? "Stop Awake" : "Keep Awake"
    }

    private var presentationTitle: String {
        model.state.presentationMode == .running ? "Stop Presenting" : "Presentation Mode"
    }
}
```

- [ ] **Step 3: Wire ContentView additively**

In `platforms/macos/Atlas/ContentView.swift`, add state and services near existing properties:

```swift
@StateObject private var keepAwakeService = KeepAwakeService()
@StateObject private var presentationModeService: PresentationModeService
@StateObject private var handMirrorService = HandMirrorService()
@StateObject private var displayControlService = DisplayControlService()
@State private var isShowingHandMirror = false
```

If `ContentView` does not currently have a custom initializer, add one that initializes `PresentationModeService` with the same `KeepAwakeService` instance:

```swift
init(paletteState: CommandPaletteState? = nil) {
    let keepAwakeService = KeepAwakeService()
    _keepAwakeService = StateObject(wrappedValue: keepAwakeService)
    _presentationModeService = StateObject(wrappedValue: PresentationModeService(keepAwakeService: keepAwakeService))
    self.paletteState = paletteState
}
```

Insert this block after the monitoring panel and before `FeatureCenterPanel`:

```swift
if isFeatureEnabled(.systemUtilities) {
    SystemUtilitiesPanel(
        model: SystemUtilitiesPanelModel(
            state: SystemUtilitiesState(
                keepAwake: keepAwakeService.status,
                presentationMode: presentationModeService.status,
                cameraPermission: handMirrorService.permissionState,
                displays: displayControlService.displays
            ),
            onToggleKeepAwake: toggleKeepAwake,
            onTogglePresentationMode: togglePresentationMode,
            onOpenHandMirror: openHandMirror,
            onRefreshDisplays: refreshDisplays
        )
    )

    Divider()
}
```

Add these methods, preserving adjacent methods already present:

```swift
private func toggleKeepAwake() {
    if keepAwakeService.status == .running {
        keepAwakeService.stop()
    } else {
        do {
            try keepAwakeService.start()
        } catch {
            showStatus(error.localizedDescription)
        }
    }
}

private func togglePresentationMode() {
    if presentationModeService.status == .running {
        presentationModeService.stop()
    } else {
        do {
            try presentationModeService.start()
        } catch {
            showStatus(error.localizedDescription)
        }
    }
}

private func openHandMirror() {
    Task {
        if await handMirrorService.prepareForPreview() {
            isShowingHandMirror = true
        }
    }
}

private func refreshDisplays() {
    do {
        try displayControlService.refreshDisplays()
    } catch {
        showStatus(error.localizedDescription)
    }
}
```

Add the sheet near existing overlay/sheet presentation code:

```swift
.sheet(isPresented: $isShowingHandMirror) {
    CameraPreviewPanel(
        permissionState: handMirrorService.permissionState,
        onRequestAccess: openHandMirror
    )
    .padding()
}
```

- [ ] **Step 4: Verify app build slice**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: the app builds with the new panel and services.

---

## Task 8: Add Command Palette Provider

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/SystemUtilitiesProvider.swift`
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Create: `platforms/macos/AtlasTests/SystemUtilitiesProviderTests.swift`

- [ ] **Step 1: Add provider tests**

Create `platforms/macos/AtlasTests/SystemUtilitiesProviderTests.swift`:

```swift
import XCTest
@testable import Atlas

final class SystemUtilitiesProviderTests: XCTestCase {
    func testDisabledFeatureReturnsNoCommands() {
        let provider = SystemUtilitiesProvider(
            isEnabled: { false },
            onToggleKeepAwake: {},
            onTogglePresentationMode: {},
            onOpenHandMirror: {},
            onRefreshDisplays: {}
        )

        XCTAssertEqual(provider.commands(matching: "awake").count, 0)
    }

    func testEnabledFeatureReturnsUtilityCommands() {
        let provider = SystemUtilitiesProvider(
            isEnabled: { true },
            onToggleKeepAwake: {},
            onTogglePresentationMode: {},
            onOpenHandMirror: {},
            onRefreshDisplays: {}
        )

        let titles = provider.commands(matching: "system").map(\.title)

        XCTAssertEqual(titles, [
            "Keep Mac Awake",
            "Presentation Mode",
            "Hand Mirror",
            "Refresh Display Capabilities",
        ])
    }

    func testCommandInvokesAction() {
        var callCount = 0
        let provider = SystemUtilitiesProvider(
            isEnabled: { true },
            onToggleKeepAwake: { callCount += 1 },
            onTogglePresentationMode: {},
            onOpenHandMirror: {},
            onRefreshDisplays: {}
        )

        guard case let .execute(action) = provider.commands(matching: "awake").first?.action else {
            return XCTFail("Expected execute action")
        }
        action()

        XCTAssertEqual(callCount, 1)
    }
}
```

- [ ] **Step 2: Add provider**

Create `platforms/macos/Atlas/CommandPalette/SystemUtilitiesProvider.swift`:

```swift
import Foundation

struct SystemUtilitiesProvider: CommandProviding {
    let isEnabled: () -> Bool
    let onToggleKeepAwake: () -> Void
    let onTogglePresentationMode: () -> Void
    let onOpenHandMirror: () -> Void
    let onRefreshDisplays: () -> Void

    func commands(matching query: String) -> [PaletteCommand] {
        guard isEnabled() else {
            return []
        }

        let commands = [
            makeCommand(
                title: "Keep Mac Awake",
                subtitle: "Toggle caffeinate keep-awake",
                icon: "cup.and.saucer",
                keywords: ["system", "awake", "caffeinate"],
                action: onToggleKeepAwake
            ),
            makeCommand(
                title: "Presentation Mode",
                subtitle: "Keep awake and mute notifications",
                icon: "person.crop.rectangle.stack",
                keywords: ["system", "presentation", "notifications", "focus"],
                action: onTogglePresentationMode
            ),
            makeCommand(
                title: "Hand Mirror",
                subtitle: "Open camera preview",
                icon: "camera",
                keywords: ["system", "camera", "mirror"],
                action: onOpenHandMirror
            ),
            makeCommand(
                title: "Refresh Display Capabilities",
                subtitle: "Detect DDC/CI support",
                icon: "display",
                keywords: ["system", "display", "brightness", "ddc"],
                action: onRefreshDisplays
            ),
        ]

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else {
            return commands
        }

        return commands.filter { command in
            command.title.lowercased().contains(trimmedQuery)
                || command.subtitle?.lowercased().contains(trimmedQuery) == true
                || command.keywords.contains(where: { $0.contains(trimmedQuery) })
        }
    }

    private func makeCommand(
        title: String,
        subtitle: String,
        icon: String,
        keywords: [String],
        action: @escaping () -> Void
    ) -> PaletteCommand {
        PaletteCommand(
            id: UUID(),
            title: title,
            subtitle: subtitle,
            icon: .sfSymbol(icon),
            keywords: keywords,
            action: .execute(action),
            category: "System Utilities"
        )
    }
}
```

- [ ] **Step 3: Wire provider additively**

In `platforms/macos/Atlas/AtlasApp.swift`, add the provider to `CommandPaletteState` without replacing existing providers:

```swift
private var isSystemUtilitiesEnabled: (() -> Bool)?
private var onToggleKeepAwake: (() -> Void)?
private var onTogglePresentationMode: (() -> Void)?
private var onOpenHandMirror: (() -> Void)?
private var onRefreshDisplays: (() -> Void)?
```

When constructing providers, add:

```swift
let systemUtilitiesProvider = SystemUtilitiesProvider(
    isEnabled: { [weak self] in self?.isSystemUtilitiesEnabled?() ?? false },
    onToggleKeepAwake: { [weak self] in self?.onToggleKeepAwake?() },
    onTogglePresentationMode: { [weak self] in self?.onTogglePresentationMode?() },
    onOpenHandMirror: { [weak self] in self?.onOpenHandMirror?() },
    onRefreshDisplays: { [weak self] in self?.onRefreshDisplays?() }
)
```

Insert `systemUtilitiesProvider` after `windowManagementProvider` in the providers array. Preserve every provider already present:

```swift
self.controller = CommandPaletteController(providers: [
    atlasProvider,
    developerToolsProvider,
    windowManagementProvider,
    systemUtilitiesProvider,
    clipboardHistoryProvider,
    snippetsProvider,
    appLauncherProvider,
])
```

Extend `setActions` additively:

```swift
func setActions(
    onCaptureDesktop: @escaping () -> Void,
    onCaptureArea: @escaping () -> Void,
    onCaptureWindow: @escaping () -> Void,
    isSystemUtilitiesEnabled: @escaping () -> Bool,
    onToggleKeepAwake: @escaping () -> Void,
    onTogglePresentationMode: @escaping () -> Void,
    onOpenHandMirror: @escaping () -> Void,
    onRefreshDisplays: @escaping () -> Void
) {
    self.onCaptureDesktop = onCaptureDesktop
    self.onCaptureArea = onCaptureArea
    self.onCaptureWindow = onCaptureWindow
    self.isSystemUtilitiesEnabled = isSystemUtilitiesEnabled
    self.onToggleKeepAwake = onToggleKeepAwake
    self.onTogglePresentationMode = onTogglePresentationMode
    self.onOpenHandMirror = onOpenHandMirror
    self.onRefreshDisplays = onRefreshDisplays
}
```

In `ContentView.startHotkeys()` or the existing place where `paletteState.setActions(...)` is called, add the new arguments while preserving all existing arguments:

```swift
paletteState?.setActions(
    onCaptureDesktop: captureDesktop,
    onCaptureArea: showSelectionWindow,
    onCaptureWindow: showWindowSelection,
    isSystemUtilitiesEnabled: { isFeatureEnabled(.systemUtilities) },
    onToggleKeepAwake: toggleKeepAwake,
    onTogglePresentationMode: togglePresentationMode,
    onOpenHandMirror: openHandMirror,
    onRefreshDisplays: refreshDisplays
)
```

- [ ] **Step 4: Verify provider tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/SystemUtilitiesProviderTests
```

Expected: disabled gating and command actions pass.

---

## Task 9: Add Xcode Project Membership

**Files:**
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add every new Swift file to the explicit PBX project**

Use Xcode or a deterministic `xcodeproj` script to add these files:

```ruby
require "xcodeproj"

project_path = "platforms/macos/Atlas.xcodeproj"
project = Xcodeproj::Project.open(project_path)
atlas_target = project.targets.find { |target| target.name == "Atlas" }
tests_target = project.targets.find { |target| target.name == "AtlasTests" }
atlas_group = project.main_group.find_subpath("Atlas", true)
palette_group = atlas_group.find_subpath("CommandPalette", true)
tests_group = project.main_group.find_subpath("AtlasTests", true)

app_files = [
  "SystemUtilitiesModels.swift",
  "SystemCommandRunner.swift",
  "KeepAwakeService.swift",
  "PresentationModeService.swift",
  "HandMirrorService.swift",
  "CameraPreviewPanel.swift",
  "DisplayControlService.swift",
  "SystemUtilitiesPanel.swift",
]

palette_files = [
  "SystemUtilitiesProvider.swift",
]

test_files = [
  "KeepAwakeServiceTests.swift",
  "PresentationModeServiceTests.swift",
  "HandMirrorServiceTests.swift",
  "DisplayControlServiceTests.swift",
  "SystemUtilitiesProviderTests.swift",
  "SystemUtilitiesPanelTests.swift",
]

app_files.each do |file|
  ref = atlas_group.files.find { |candidate| candidate.path == file } || atlas_group.new_file(file)
  atlas_target.add_file_references([ref]) unless atlas_target.source_build_phase.files_references.include?(ref)
end

palette_files.each do |file|
  ref = palette_group.files.find { |candidate| candidate.path == file } || palette_group.new_file(file)
  atlas_target.add_file_references([ref]) unless atlas_target.source_build_phase.files_references.include?(ref)
end

test_files.each do |file|
  ref = tests_group.files.find { |candidate| candidate.path == file } || tests_group.new_file(file)
  tests_target.add_file_references([ref]) unless tests_target.source_build_phase.files_references.include?(ref)
end

project.save
```

If the repo does not have the `xcodeproj` gem available, make the same additions manually in `platforms/macos/Atlas.xcodeproj/project.pbxproj`:

- Add one `PBXFileReference` for each new Swift app and test file.
- Add one `PBXBuildFile` for each new Swift app and test file.
- Add app files to the `Atlas` group or `Atlas/CommandPalette` group.
- Add test files to the `AtlasTests` group.
- Add app build files to the `Atlas` `PBXSourcesBuildPhase`.
- Add test build files to the `AtlasTests` `PBXSourcesBuildPhase`.

- [ ] **Step 2: Verify project membership**

Run:

```bash
rg -n 'SystemUtilitiesModels|SystemCommandRunner|KeepAwakeService|PresentationModeService|HandMirrorService|CameraPreviewPanel|DisplayControlService|SystemUtilitiesPanel|SystemUtilitiesProvider|KeepAwakeServiceTests|PresentationModeServiceTests|HandMirrorServiceTests|DisplayControlServiceTests|SystemUtilitiesProviderTests|SystemUtilitiesPanelTests' platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: each new Swift file appears as a file reference and source build file. App files appear in the `Atlas` source build phase; test files appear in the `AtlasTests` source build phase.

---

## Task 10: Run Focused and Full Verification

**Files:**
- No file changes

- [ ] **Step 1: Run focused XCTest slice**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -only-testing:AtlasTests/FeatureModelsTests \
  -only-testing:AtlasTests/KeepAwakeServiceTests \
  -only-testing:AtlasTests/PresentationModeServiceTests \
  -only-testing:AtlasTests/HandMirrorServiceTests \
  -only-testing:AtlasTests/DisplayControlServiceTests \
  -only-testing:AtlasTests/SystemUtilitiesProviderTests \
  -only-testing:AtlasTests/SystemUtilitiesPanelTests
```

Expected: the focused system utilities and feature mapping tests pass.

- [ ] **Step 2: Run Rust feature registry test**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
```

Expected: the feature registry lists `system-utilities` and remains sorted.

- [ ] **Step 3: Run full app build**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: the app builds with all new Swift files included in the explicit Xcode project.

---

## Acceptance Criteria

- `system-utilities` is disabled by default in Feature Center.
- When disabled, the System Utilities panel is hidden and command palette provider returns no commands.
- Keep-awake starts one injected `/usr/bin/caffeinate -dimsu` process and stops it on toggle.
- Presentation mode starts keep-awake and runs notification mute/unmute through injected command adapters.
- Hand mirror requests camera permission only when state is `notDetermined`, opens preview only when authorized, and shows denied/restricted states without starting camera capture.
- Display control reports DDC/CI capability detection and unavailable probe failures without changing brightness.
- All new Swift app and test files are members of the explicit Xcode project targets.
- Focused XCTest, Rust feature test, and app build commands pass.

## Implementation Notes

- Keep command adapters injectable. Tests must not depend on live `caffeinate`, `osascript`, `ddcctl`, camera hardware, external displays, or current notification settings.
- Preserve adjacent child-plan enum cases, provider lists, and command palette builders. Do not replace `AtlasModule`, `CommandPaletteController`, `CommandPaletteView`, or `CommandPaletteState` with closed-list snippets.
- The notification mute script is intentionally isolated behind `SystemCommandRunning` because macOS Automation permission behavior varies. UI must report failures instead of assuming permission is available.
- `CameraPreviewPanel` requires camera usage text in app metadata if the Xcode target does not already include it. Add `NSCameraUsageDescription` with a concise value such as `Atlas uses the camera for the hand mirror preview.` before running on a real machine.
- DDC/CI detection is best-effort. Treat missing `ddcctl` or unsupported displays as unavailable, not as an error that breaks the panel.
