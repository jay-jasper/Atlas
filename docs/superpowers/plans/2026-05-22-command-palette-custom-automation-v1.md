# Command Palette Custom Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user-defined command palette automations for shell and Python commands, with local storage, explicit execution warnings, timeout handling, output display, Feature Center gating, frecency ranking, and deterministic tests through injected process runners.

**Architecture:** Keep automation in Swift for this version. Command definitions are stored locally as JSON through a small store. Execution is isolated behind `AutomationProcessRunning` so tests never spawn real processes. The command palette discovers stored automations through a `CustomAutomationProvider`; executing an automation pushes an output view instead of dismissing the palette.

**Tech Stack:** SwiftUI, AppKit, Foundation `Process`, JSON file storage, UserDefaults-backed command usage records, XCTest, Rust Feature Center registry, UniFFI feature list/toggle bridge.

---

**Scope:** This plan adds the first production implementation for custom command automation. It does not add scheduled/background automations, network triggers, AI skills, cloud sync, or a visual workflow builder.

## Files

- Modify: `crates/atlas-core/src/features.rs`
- Read: `crates/atlas-ffi/src/atlas.udl`
- Read: `crates/atlas-ffi/src/lib.rs`
- Modify: `platforms/macos/Atlas/AtlasModule.swift`
- Modify: `platforms/macos/Atlas/FeatureModels.swift`
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
- Modify: `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`
- Modify: `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`
- Create: `platforms/macos/Atlas/CommandPalette/CustomAutomationModels.swift`
- Create: `platforms/macos/Atlas/CommandPalette/CustomAutomationStore.swift`
- Create: `platforms/macos/Atlas/CommandPalette/AutomationProcessRunner.swift`
- Create: `platforms/macos/Atlas/CommandPalette/CustomAutomationProvider.swift`
- Create: `platforms/macos/Atlas/CommandPalette/AutomationOutputView.swift`
- Create: `platforms/macos/Atlas/AutomationSettingsView.swift`
- Modify: `platforms/macos/Atlas/AtlasSettingsView.swift`
- Create: `platforms/macos/AtlasTests/CustomAutomationStoreTests.swift`
- Create: `platforms/macos/AtlasTests/CustomAutomationProviderTests.swift`
- Create: `platforms/macos/AtlasTests/AutomationOutputViewTests.swift`
- Modify: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

Project membership rule: every new Swift app file must be added to the `Atlas` target sources in `platforms/macos/Atlas.xcodeproj/project.pbxproj`, and every new Swift test file must be added to the `AtlasTests` target sources before running the relevant `xcodebuild test` command.

## Task 1: Feature Center Gate

- [ ] **Step 1: Add the Rust feature name**

In `crates/atlas-core/src/features.rs`, update `FeatureManager::new()` and `test_list_features_is_sorted_by_name()`:

```rust
features.insert("automation".to_string(), FeatureStatus::Disabled);
features.insert("monitoring".to_string(), FeatureStatus::Disabled);
features.insert("screenshot".to_string(), FeatureStatus::Disabled);
features.insert("window-manager".to_string(), FeatureStatus::Disabled);
```

```rust
assert_eq!(names, ["automation", "monitoring", "screenshot", "window-manager"]);
```

- [ ] **Step 2: Confirm UniFFI does not need a new API shape**

Read `crates/atlas-ffi/src/atlas.udl` and `crates/atlas-ffi/src/lib.rs`.

Expected: No edits are needed. The existing `list_features()` and `toggle_feature(name:enabled:)` API exposes Feature Center entries from `FeatureManager`, so adding `"automation"` in `crates/atlas-core/src/features.rs` is enough for Swift to discover and toggle the feature.

- [ ] **Step 3: Add the Swift module entry**

In `platforms/macos/Atlas/AtlasModule.swift`, replace the enum with:

```swift
enum AtlasModule: String, CaseIterable, Identifiable {
    case automation
    case screenshot
    case monitoring

    var id: String { rawValue }

    var featureName: String {
        switch self {
        case .automation:
            return "automation"
        case .screenshot:
            return "screenshot"
        case .monitoring:
            return "monitoring"
        }
    }

    var title: String {
        switch self {
        case .automation:
            return "Automation"
        case .screenshot:
            return "Screenshot"
        case .monitoring:
            return "Monitoring"
        }
    }
}
```

In `platforms/macos/Atlas/FeatureModels.swift`, add:

```swift
case AtlasModule.automation.featureName:
    return AtlasModule.automation.title
```

- [ ] **Step 4: Verify feature behavior**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureModelsTests
```

Expected: Rust feature ordering and Swift feature title tests pass.

## Task 2: Automation Models and Store

- [ ] **Step 1: Add automation models**

Create `platforms/macos/Atlas/CommandPalette/CustomAutomationModels.swift`:

```swift
import Foundation

enum CustomAutomationKind: String, Codable, Equatable, CaseIterable, Sendable {
    case shell
    case python

    var title: String {
        switch self {
        case .shell:
            return "Shell"
        case .python:
            return "Python"
        }
    }
}

struct CustomAutomationCommand: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var command: String
    var kind: CustomAutomationKind
    var keywords: [String]
    var timeoutSeconds: TimeInterval
    var requiresConfirmation: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        command: String,
        kind: CustomAutomationKind,
        keywords: [String] = [],
        timeoutSeconds: TimeInterval = 10,
        requiresConfirmation: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.command = command
        self.kind = kind
        self.keywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.timeoutSeconds = timeoutSeconds
        self.requiresConfirmation = requiresConfirmation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isValid: Bool {
        !title.isEmpty && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && timeoutSeconds > 0
    }
}
```

- [ ] **Step 2: Add JSON-backed storage**

Create `platforms/macos/Atlas/CommandPalette/CustomAutomationStore.swift`:

```swift
import Foundation

protocol CustomAutomationStoring {
    func commands() -> [CustomAutomationCommand]
    func save(_ commands: [CustomAutomationCommand]) throws
    func upsert(_ command: CustomAutomationCommand) throws
    func delete(id: UUID) throws
}

enum CustomAutomationStoreError: LocalizedError, Equatable {
    case invalidCommand
    case duplicateTitle

    var errorDescription: String? {
        switch self {
        case .invalidCommand:
            return "Automation commands require a title, command text, and positive timeout."
        case .duplicateTitle:
            return "Automation command titles must be unique."
        }
    }
}

final class CustomAutomationStore: CustomAutomationStoring {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = CustomAutomationStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func commands() -> [CustomAutomationCommand] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([CustomAutomationCommand].self, from: data)) ?? []
    }

    func save(_ commands: [CustomAutomationCommand]) throws {
        guard commands.allSatisfy(\.isValid) else {
            throw CustomAutomationStoreError.invalidCommand
        }
        let normalizedTitles = commands.map { $0.title.lowercased() }
        guard Set(normalizedTitles).count == normalizedTitles.count else {
            throw CustomAutomationStoreError.duplicateTitle
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(commands).write(to: fileURL, options: [.atomic])
    }

    func upsert(_ command: CustomAutomationCommand) throws {
        guard command.isValid else {
            throw CustomAutomationStoreError.invalidCommand
        }
        var current = commands()
        if let index = current.firstIndex(where: { $0.id == command.id }) {
            current[index] = command
        } else {
            current.append(command)
        }
        try save(current.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
    }

    func delete(id: UUID) throws {
        try save(commands().filter { $0.id != id })
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("custom-automation.json")
    }
}
```

- [ ] **Step 3: Add new files to the Xcode project**

Modify `platforms/macos/Atlas.xcodeproj/project.pbxproj` so these app files are included in the `Atlas` target sources:

- `platforms/macos/Atlas/CommandPalette/CustomAutomationModels.swift`
- `platforms/macos/Atlas/CommandPalette/CustomAutomationStore.swift`

Modify the same project file so this test file is included in the `AtlasTests` target sources:

- `platforms/macos/AtlasTests/CustomAutomationStoreTests.swift`

- [ ] **Step 4: Add store tests**

Create `platforms/macos/AtlasTests/CustomAutomationStoreTests.swift` with tests for empty load, save/load round trip, sorted upsert, delete, invalid empty title, invalid empty command, invalid timeout, and duplicate title rejection.

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/CustomAutomationStoreTests
```

Expected: Store tests pass without touching real Application Support by using a temporary file URL.

## Task 3: Injected Process Runner

- [ ] **Step 1: Add process result and runner protocol**

Create `platforms/macos/Atlas/CommandPalette/AutomationProcessRunner.swift`:

```swift
import Foundation

struct AutomationProcessResult: Equatable, Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
    let didTimeOut: Bool
    let duration: TimeInterval
}

protocol AutomationProcessRunning {
    func run(_ command: CustomAutomationCommand) async -> AutomationProcessResult
}

final class SystemAutomationProcessRunner: AutomationProcessRunning {
    private let dateProvider: () -> Date
    private let pollInterval: TimeInterval = 0.05
    private let shutdownGracePeriod: TimeInterval = 0.5

    init(dateProvider: @escaping () -> Date = Date.init) {
        self.dateProvider = dateProvider
    }

    func run(_ command: CustomAutomationCommand) async -> AutomationProcessResult {
        let startedAt = dateProvider()
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputBuffer = LockedDataBuffer()
        let errorBuffer = LockedDataBuffer()

        switch command.kind {
        case .shell:
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command.command]
        case .python:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", command.command]
        }

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputBuffer.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorBuffer.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            return AutomationProcessResult(
                exitCode: -1,
                standardOutput: "",
                standardError: error.localizedDescription,
                didTimeOut: false,
                duration: dateProvider().timeIntervalSince(startedAt)
            )
        }

        let timedOut = await waitBounded(for: process, timeout: command.timeoutSeconds)
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()

        let stdout = String(data: outputBuffer.data(), encoding: .utf8) ?? ""
        let stderr = String(data: errorBuffer.data(), encoding: .utf8) ?? ""

        return AutomationProcessResult(
            exitCode: timedOut ? -9 : process.terminationStatus,
            standardOutput: stdout,
            standardError: stderr,
            didTimeOut: timedOut,
            duration: dateProvider().timeIntervalSince(startedAt)
        )
    }

    private func waitBounded(for process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(max(timeout, 0.1))
        while process.isRunning && Date() < deadline {
            await sleepPollInterval()
        }
        guard process.isRunning else { return false }

        process.terminate()
        let terminateDeadline = Date().addingTimeInterval(shutdownGracePeriod)
        while process.isRunning && Date() < terminateDeadline {
            await sleepPollInterval()
        }
        guard process.isRunning else { return true }

        process.interrupt()
        let interruptDeadline = Date().addingTimeInterval(shutdownGracePeriod)
        while process.isRunning && Date() < interruptDeadline {
            await sleepPollInterval()
        }

        return true
    }

    private func sleepPollInterval() async {
        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
```

- [ ] **Step 2: Keep process execution tests injected**

Modify `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `platforms/macos/Atlas/CommandPalette/AutomationProcessRunner.swift` is included in the `Atlas` target sources before running any test target that imports automation types.

Do not add XCTest coverage that starts `/bin/zsh`, `/usr/bin/python3`, or any other real process. The production `SystemAutomationProcessRunner` is covered by direct code review and by higher-level tests that inject fake `AutomationProcessRunning` implementations.

Timeout, stdout, stderr, and non-zero exit behavior are verified in `platforms/macos/AtlasTests/AutomationOutputViewTests.swift` by returning deterministic `AutomationProcessResult` values from a fake runner:

```swift
private final class FakeAutomationRunner: AutomationProcessRunning {
    private(set) var executed: [CustomAutomationCommand] = []
    var result = AutomationProcessResult(
        exitCode: 0,
        standardOutput: "ok",
        standardError: "",
        didTimeOut: false,
        duration: 0.1
    )

    func run(_ command: CustomAutomationCommand) async -> AutomationProcessResult {
        executed.append(command)
        return result
    }
}
```

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/AutomationOutputViewTests
```

Expected: Output tests pass with fake runner results. No test starts a real shell, Python interpreter, or `Process`.

## Task 4: Provider, Output Destination, and Ranking

- [ ] **Step 1: Add a palette destination for automation output**

In `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`, update `PaletteDestination`:

```swift
enum PaletteDestination: Equatable {
    case windowPicker
    case screenshotLibrary
    case portLookup
    case automationOutput(CustomAutomationCommand)
}
```

- [ ] **Step 2: Add provider**

Create `platforms/macos/Atlas/CommandPalette/CustomAutomationProvider.swift`:

```swift
import Foundation

final class CustomAutomationProvider: CommandProviding {
    private let store: CustomAutomationStoring
    private let isEnabled: () -> Bool

    init(
        store: CustomAutomationStoring = CustomAutomationStore(),
        isEnabled: @escaping () -> Bool
    ) {
        self.store = store
        self.isEnabled = isEnabled
    }

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return store.commands()
            .filter { command in
                command.title.localizedCaseInsensitiveContains(trimmed)
                    || command.command.localizedCaseInsensitiveContains(trimmed)
                    || command.kind.title.localizedCaseInsensitiveContains(trimmed)
                    || command.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
            .prefix(5)
            .map { command in
                PaletteCommand(
                    id: command.id,
                    title: "Run \(command.title)",
                    subtitle: "\(command.kind.title) automation",
                    icon: .sfSymbol(command.kind == .python ? "curlybraces" : "terminal"),
                    keywords: command.keywords + [command.kind.rawValue, "automation", "run"],
                    action: .push(.automationOutput(command)),
                    category: "Automation"
                )
            }
    }
}
```

The provider uses existing `CommandPaletteRanker` automatically because `CommandPaletteView.rankedResults()` already ranks every provider's result list against `CommandUsageStore`. The existing `CommandUsageStore.commandKey(for:)` uses `category|title`, not `PaletteCommand.id`, so this plan keeps automation command titles unique enough for ranking. No usage-store key migration is part of this plan.

- [ ] **Step 3: Add provider tests**

Modify `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `platforms/macos/Atlas/CommandPalette/CustomAutomationProvider.swift` is included in the `Atlas` target sources.

Modify the same project file so `platforms/macos/AtlasTests/CustomAutomationProviderTests.swift` is included in the `AtlasTests` target sources.

Create `platforms/macos/AtlasTests/CustomAutomationProviderTests.swift` with:

- disabled Feature Center gate returns no results
- blank query returns no results
- query matches title, command body, kind, and keywords
- results are capped to five
- result category is `Automation`
- result action is `.push(.automationOutput(command))`
- generated command titles include the user-defined automation title, producing stable `CommandUsageStore` keys such as `Automation|Run Deploy Preview`
- duplicate automation titles are rejected in `CustomAutomationStore`, so frecency does not merge two different automation commands under the same `category|title` key

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/CustomAutomationProviderTests -only-testing:AtlasTests/CommandPaletteRankerTests -only-testing:AtlasTests/CommandUsageStoreTests
```

Expected: Provider, ranking, and usage-store tests pass.

## Task 5: Output Display and Permission Warning

- [ ] **Step 1: Add output view**

Create `platforms/macos/Atlas/CommandPalette/AutomationOutputView.swift`:

```swift
import SwiftUI

@MainActor
final class AutomationOutputViewModel: ObservableObject {
    @Published private(set) var result: AutomationProcessResult?
    @Published private(set) var isRunning = false
    @Published var hasConfirmed = false

    let command: CustomAutomationCommand
    private let runner: AutomationProcessRunning

    init(command: CustomAutomationCommand, runner: AutomationProcessRunning) {
        self.command = command
        self.runner = runner
    }

    func run() {
        guard !isRunning else { return }
        guard !command.requiresConfirmation || hasConfirmed else { return }
        isRunning = true
        Task {
            let result = await runner.run(command)
            self.result = result
            self.isRunning = false
        }
    }
}

enum AutomationOutputFormatter {
    static func statusText(for result: AutomationProcessResult, timeoutSeconds: TimeInterval) -> String {
        if result.didTimeOut {
            return "Timed out after \(Int(timeoutSeconds))s"
        }
        return "Exited with code \(result.exitCode)"
    }

    static func displayText(for result: AutomationProcessResult) -> String {
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if stdout.isEmpty && stderr.isEmpty { return "No output" }
        if stderr.isEmpty { return stdout }
        if stdout.isEmpty { return stderr }
        return "\(stdout)\n\n\(stderr)"
    }
}

struct AutomationOutputView: View {
    @StateObject private var model: AutomationOutputViewModel

    init(command: CustomAutomationCommand, runner: AutomationProcessRunning) {
        _model = StateObject(wrappedValue: AutomationOutputViewModel(command: command, runner: runner))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.command.title)
                .font(.headline)

            if model.command.requiresConfirmation && !model.hasConfirmed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("This automation can run local code on your Mac.", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(model.command.command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Allow and Run") {
                        model.hasConfirmed = true
                        model.run()
                    }
                }
            } else if model.isRunning {
                ProgressView("Running...")
            } else if let result = model.result {
                output(result)
            } else {
                Button("Run") { model.run() }
            }
        }
        .padding()
        .onAppear {
            if !model.command.requiresConfirmation {
                model.hasConfirmed = true
                model.run()
            }
        }
    }

    private func output(_ result: AutomationProcessResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                AutomationOutputFormatter.statusText(for: result, timeoutSeconds: model.command.timeoutSeconds),
                systemImage: result.exitCode == 0 && !result.didTimeOut ? "checkmark.circle" : "xmark.octagon"
            )
            ScrollView {
                Text(AutomationOutputFormatter.displayText(for: result))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
        }
    }
}
```

- [ ] **Step 2: Add new files to the Xcode project**

Modify `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `platforms/macos/Atlas/CommandPalette/AutomationOutputView.swift` is included in the `Atlas` target sources.

Modify the same project file so `platforms/macos/AtlasTests/AutomationOutputViewTests.swift` is included in the `AtlasTests` target sources.

- [ ] **Step 3: Wire output destination**

In `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`, add a runner property and initializer argument:

```swift
private let automationRunner: AutomationProcessRunning
```

```swift
automationRunner: AutomationProcessRunning = SystemAutomationProcessRunner()
```

In `subView(for:)`, add:

```swift
case .automationOutput(let command):
    AutomationOutputView(command: command, runner: automationRunner)
```

- [ ] **Step 4: Add output tests**

Create `platforms/macos/AtlasTests/AutomationOutputViewTests.swift` with view model tests and a fake runner:

```swift
private final class FakeAutomationRunner: AutomationProcessRunning {
    private(set) var executed: [CustomAutomationCommand] = []
    var result = AutomationProcessResult(
        exitCode: 0,
        standardOutput: "ok",
        standardError: "",
        didTimeOut: false,
        duration: 0.1
    )

    func run(_ command: CustomAutomationCommand) async -> AutomationProcessResult {
        executed.append(command)
        return result
    }
}
```

Tests instantiate `AutomationOutputViewModel` directly and assert:

- confirmation-required commands do not run before confirmation
- setting `hasConfirmed = true` and calling `run()` executes exactly once
- no-confirmation commands run when `hasConfirmed` is initialized to true by the test before `run()`
- `AutomationOutputFormatter.displayText(for:)` returns stdout for success
- `AutomationOutputFormatter.displayText(for:)` returns stderr for failure
- `AutomationOutputFormatter.statusText(for:timeoutSeconds:)` returns timeout status for timed-out results

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/AutomationOutputViewTests
```

Expected: Output tests pass with fake runner and no real process execution.

## Task 6: Settings UI for User-Defined Commands

- [ ] **Step 1: Add settings view**

Create `platforms/macos/Atlas/AutomationSettingsView.swift` with:

- a list of stored commands
- add/edit/delete controls
- segmented picker for Shell/Python
- title, command text, keywords, timeout, and confirmation fields
- inline warning text: "Shell and Python automations can read files, modify files, and run local programs. Only save commands you trust."
- save validation using `CustomAutomationCommand.isValid`

Use `CustomAutomationStore` through `CustomAutomationStoring` so tests can inject an in-memory store.

- [ ] **Step 2: Add settings section**

Modify `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `platforms/macos/Atlas/AutomationSettingsView.swift` is included in the `Atlas` target sources before running the settings build.

In `platforms/macos/Atlas/AtlasSettingsView.swift`, add a "Custom Automation" section below the existing Command Palette section:

```swift
Section("Custom Automation") {
    AutomationSettingsView(store: CustomAutomationStore())
}
```

Do not expose this settings section as a replacement for Feature Center gating. Feature Center controls whether custom automation commands appear and run from the palette.

- [ ] **Step 3: Verify settings build**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: The macOS app builds.

## Task 7: Register Provider Behind Feature Center

- [ ] **Step 1: Register provider**

In `platforms/macos/Atlas/AtlasApp.swift`, add the provider:

```swift
let customAutomationProvider = CustomAutomationProvider(
    store: CustomAutomationStore(),
    isEnabled: {
        let features = (try? AtlasBridge.listFeatures()) ?? []
        return features.contains {
            $0.name == AtlasModule.automation.featureName && $0.isEnabled
        }
    }
)
```

Add `customAutomationProvider` before `appLauncherProvider` in the provider array so app launching remains the broad fallback provider:

```swift
customAutomationProvider,
appLauncherProvider,
```

- [ ] **Step 2: Verify the command palette slice**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/CommandPaletteModelsTests -only-testing:AtlasTests/AtlasCommandProviderTests -only-testing:AtlasTests/CommandPaletteRankerTests -only-testing:AtlasTests/CommandUsageStoreTests -only-testing:AtlasTests/AppLauncherProviderTests -only-testing:AtlasTests/DeveloperToolsProviderTests -only-testing:AtlasTests/SnippetsProviderTests -only-testing:AtlasTests/WindowManagementProviderTests -only-testing:AtlasTests/CustomAutomationStoreTests -only-testing:AtlasTests/CustomAutomationProviderTests -only-testing:AtlasTests/AutomationOutputViewTests
```

Expected: All listed command palette and automation tests pass.

## Task 8: Final Verification and Commit

- [ ] **Step 1: Run narrow verification**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureModelsTests -only-testing:AtlasTests/CustomAutomationStoreTests -only-testing:AtlasTests/CustomAutomationProviderTests -only-testing:AtlasTests/AutomationOutputViewTests
```

Expected: Rust feature and custom automation tests pass. Custom automation tests use fake injected process runners and do not start real shell or Python processes.

- [ ] **Step 2: Run broader Swift verification**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: Full macOS XCTest suite passes.

- [ ] **Step 3: Inspect diff**

Run:

```bash
git diff -- crates/atlas-core/src/features.rs crates/atlas-ffi/src/atlas.udl crates/atlas-ffi/src/lib.rs platforms/macos/Atlas platforms/macos/AtlasTests platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: Diff contains only Feature Center gating, custom automation storage/execution/provider/output/settings code, tests, and Xcode project source membership for the new Swift files.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add crates/atlas-core/src/features.rs crates/atlas-ffi/src/atlas.udl crates/atlas-ffi/src/lib.rs platforms/macos/Atlas platforms/macos/AtlasTests platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add custom command automation"
```

Expected: Commit succeeds. No roadmap or unrelated files are included unless this implementation plan is also being marked complete in the same change.

## Acceptance Criteria

- User-defined shell and Python commands can be stored locally and edited from Settings.
- Automation commands appear in the command palette only when the `automation` Feature Center module is enabled.
- Automation command execution shows a permission warning before running commands that require confirmation.
- Shell commands execute through `/bin/zsh -lc`; Python commands execute through `/usr/bin/python3 -c`.
- Execution has a per-command timeout and reports timeout separately from non-zero exit status.
- Output view displays stdout, stderr, exit code, timeout state, and empty-output state.
- Command palette frecency ranking works for automation commands through unique generated `Automation|Run <title>` usage keys in existing `CommandUsageStore`.
- Unit tests cover storage, provider filtering/gating, output view behavior, timeout behavior, and execution flow using injected fake runners. Tests do not start real shell or Python processes.
