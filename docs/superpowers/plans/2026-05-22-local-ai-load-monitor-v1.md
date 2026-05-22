# Local AI Load Monitor V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a gated local AI load monitor that detects Ollama and LM Studio, attributes CPU and memory to their processes, reports best-effort GPU/NPU hints, and displays the result in the macOS menu bar panel.

**Architecture:** Implement the first version in Swift using injected process snapshots so tests never depend on the developer machine's live process table. Detection is local-only: classify known Ollama and LM Studio process names and bundle paths, then aggregate CPU and memory across matching processes. GPU/NPU reporting is explicitly best-effort and is represented as unavailable unless injected samplers provide data.

**Tech Stack:** SwiftUI, Foundation, Process for `ps` snapshots in live mode, XCTest with injected snapshots, Rust Feature Center registry, UniFFI feature list/toggle bridge.

---

**Scope:** This plan adds local AI process detection, process-level CPU/memory attribution, best-effort accelerator reporting, UI display, Feature Center gating, and deterministic tests. It does not add Rust FFI, vendor-specific private GPU APIs, background agents, model-level token accounting, or production TokenBar cost logic.

## Files

- Modify: `crates/atlas-core/src/features.rs`
- Modify: `platforms/macos/Atlas/AtlasModule.swift`
- Modify: `platforms/macos/Atlas/FeatureModels.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
- Create: `platforms/macos/Atlas/LocalAILoadModels.swift`
- Create: `platforms/macos/Atlas/LocalAIProcessSnapshot.swift`
- Create: `platforms/macos/Atlas/LocalAILoadMonitor.swift`
- Create: `platforms/macos/Atlas/LocalAILoadRefreshService.swift`
- Create: `platforms/macos/Atlas/LocalAILoadPanel.swift`
- Create: `platforms/macos/AtlasTests/LocalAILoadMonitorTests.swift`
- Create: `platforms/macos/AtlasTests/LocalAILoadRefreshServiceTests.swift`
- Create: `platforms/macos/AtlasTests/LocalAIProcessSnapshotTests.swift`
- Modify: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

Project membership rule: every new Swift app file must be added to the `Atlas` target sources in `platforms/macos/Atlas.xcodeproj/project.pbxproj`, and every new Swift test file must be added to the `AtlasTests` target sources before running the relevant `xcodebuild test` commands.

## Task 1: Feature Center Gate

**Files:**
- Modify: `crates/atlas-core/src/features.rs`
- Modify: `platforms/macos/Atlas/AtlasModule.swift`
- Modify: `platforms/macos/Atlas/FeatureModels.swift`
- Modify: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

- [x] **Step 1: Add the Rust feature name**

In `crates/atlas-core/src/features.rs`, update `FeatureManager::new()`:

```rust
features.insert("ai-load-monitor".to_string(), FeatureStatus::Disabled);
features.insert("monitoring".to_string(), FeatureStatus::Disabled);
features.insert("screenshot".to_string(), FeatureStatus::Disabled);
features.insert("window-manager".to_string(), FeatureStatus::Disabled);
```

Update `test_list_features_is_sorted_by_name()`:

```rust
assert_eq!(names, ["ai-load-monitor", "monitoring", "screenshot", "window-manager"]);
```

If this plan is implemented after TokenBar, preserve both names:

```rust
assert_eq!(names, ["ai-load-monitor", "monitoring", "screenshot", "tokenbar", "window-manager"]);
```

- [x] **Step 2: Add the Swift module case**

Update `platforms/macos/Atlas/AtlasModule.swift` by adding `aiLoadMonitor` to the existing enum. Do not replace the whole file if another plan has already added modules. If TokenBar is already present, preserve `case tokenbar` and its title mapping:

```swift
enum AtlasModule: String, CaseIterable, Identifiable {
    case screenshot
    case monitoring
    case aiLoadMonitor = "ai-load-monitor"
    case tokenbar // Keep if already present.

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
        case .aiLoadMonitor:
            return "AI Load"
        case .tokenbar:
            return "TokenBar"
        }
    }
}
```

If `tokenbar` is not present yet, add only `case aiLoadMonitor = "ai-load-monitor"` and the `AI Load` switch branch.

- [x] **Step 3: Add title mapping and tests**

In `platforms/macos/Atlas/FeatureModels.swift`, add:

```swift
case AtlasModule.aiLoadMonitor.featureName:
    return AtlasModule.aiLoadMonitor.title
```

Append this test to `platforms/macos/AtlasTests/FeatureModelsTests.swift`:

```swift
func testMapsAILoadTitle() {
    let feature = AtlasFeature(name: "ai-load-monitor", isEnabled: false)

    XCTAssertEqual(feature.title, "AI Load")
}
```

- [x] **Step 4: Verify the gate**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureModelsTests
```

Expected: Rust feature ordering and Swift title tests pass.

## Task 2: Process Snapshot Collection

**Files:**
- Create: `platforms/macos/Atlas/LocalAILoadModels.swift`
- Create: `platforms/macos/Atlas/LocalAIProcessSnapshot.swift`
- Create: `platforms/macos/AtlasTests/LocalAIProcessSnapshotTests.swift`

- [x] **Step 1: Add process snapshot parsing test**

Create `platforms/macos/AtlasTests/LocalAIProcessSnapshotTests.swift`:

```swift
import XCTest
@testable import Atlas

final class LocalAIProcessSnapshotTests: XCTestCase {
    func testParsesProcessSnapshotRows() throws {
        let output = """
        123 12.5 102400 /Applications/Ollama.app/Contents/MacOS/Ollama serve
        456 3.0 204800 /Applications/LM Studio.app/Contents/MacOS/LM Studio --server
        """

        let rows = LocalAIProcessSnapshotParser.parse(output)

        XCTAssertEqual(rows, [
            LocalAIProcessSnapshot(pid: 123, cpuPercent: 12.5, residentMemoryBytes: 102400 * 1024, command: "/Applications/Ollama.app/Contents/MacOS/Ollama serve"),
            LocalAIProcessSnapshot(pid: 456, cpuPercent: 3.0, residentMemoryBytes: 204800 * 1024, command: "/Applications/LM Studio.app/Contents/MacOS/LM Studio --server"),
        ])
    }
}
```

- [x] **Step 2: Add load models**

Create `platforms/macos/Atlas/LocalAILoadModels.swift`:

```swift
import Foundation

enum LocalAIProvider: String, Equatable, Sendable {
    case ollama
    case lmStudio

    var title: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .lmStudio:
            return "LM Studio"
        }
    }
}

struct LocalAIProcessSnapshot: Equatable, Sendable {
    let pid: Int
    let cpuPercent: Double
    let residentMemoryBytes: UInt64
    let command: String
}

struct LocalAIProviderLoad: Equatable, Identifiable, Sendable {
    var id: LocalAIProvider { provider }
    let provider: LocalAIProvider
    let processCount: Int
    let cpuPercent: Double
    let residentMemoryBytes: UInt64
    let accelerator: LocalAIAcceleratorLoad
}

struct LocalAIAcceleratorLoad: Equatable, Sendable {
    let label: String
    let utilizationPercent: Double?
    let memoryBytes: UInt64?

    static let unavailable = LocalAIAcceleratorLoad(label: "GPU/NPU unavailable", utilizationPercent: nil, memoryBytes: nil)
}

struct LocalAILoadSnapshot: Equatable, Sendable {
    let providers: [LocalAIProviderLoad]
    let capturedAt: Date

    static let empty = LocalAILoadSnapshot(providers: [], capturedAt: Date(timeIntervalSince1970: 0))
}
```

- [x] **Step 3: Add live `ps` snapshot source**

Create `platforms/macos/Atlas/LocalAIProcessSnapshot.swift`:

```swift
import Foundation

protocol LocalAIProcessSnapshotting {
    func snapshots() throws -> [LocalAIProcessSnapshot]
}

struct LocalAIProcessSnapshotParser {
    static func parse(_ output: String) -> [LocalAIProcessSnapshot] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = UInt64(parts[2]) else {
                return nil
            }
            return LocalAIProcessSnapshot(pid: pid, cpuPercent: cpu, residentMemoryBytes: rssKB * 1024, command: String(parts[3]))
        }
    }
}

struct LocalAIProcessSnapshotter: LocalAIProcessSnapshotting {
    func snapshots() throws -> [LocalAIProcessSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return LocalAIProcessSnapshotParser.parse(String(decoding: data, as: UTF8.self))
    }
}
```

- [x] **Step 4: Verify parser**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/LocalAIProcessSnapshotTests
```

Expected: Parser tests pass after project membership is added in Task 6.

## Task 3: Ollama, LM Studio, CPU, Memory, GPU, and NPU Attribution

**Files:**
- Create: `platforms/macos/Atlas/LocalAILoadMonitor.swift`
- Create: `platforms/macos/AtlasTests/LocalAILoadMonitorTests.swift`
- Create: `platforms/macos/Atlas/LocalAILoadRefreshService.swift`
- Create: `platforms/macos/AtlasTests/LocalAILoadRefreshServiceTests.swift`

- [x] **Step 1: Add monitor tests with injected process snapshots**

Create `platforms/macos/AtlasTests/LocalAILoadMonitorTests.swift`:

```swift
import XCTest
@testable import Atlas

final class LocalAILoadMonitorTests: XCTestCase {
    func testDetectsOllamaAndLMStudioAndAggregatesCPUAndMemory() throws {
        let source = StaticLocalAIProcessSnapshotter(snapshots: [
            LocalAIProcessSnapshot(pid: 100, cpuPercent: 20.5, residentMemoryBytes: 1_000, command: "/Applications/Ollama.app/Contents/MacOS/Ollama serve"),
            LocalAIProcessSnapshot(pid: 101, cpuPercent: 5.0, residentMemoryBytes: 2_000, command: "ollama runner --model llama3"),
            LocalAIProcessSnapshot(pid: 200, cpuPercent: 10.0, residentMemoryBytes: 4_000, command: "/Applications/LM Studio.app/Contents/MacOS/LM Studio --server"),
            LocalAIProcessSnapshot(pid: 300, cpuPercent: 99.0, residentMemoryBytes: 8_000, command: "/usr/bin/OtherApp"),
        ])
        let monitor = LocalAILoadMonitor(processSnapshotter: source, acceleratorSampler: StaticLocalAIAcceleratorSampler(loads: [.ollama: LocalAIAcceleratorLoad(label: "Apple Neural Engine", utilizationPercent: nil, memoryBytes: nil)]))

        let snapshot = try monitor.snapshot(now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(snapshot.providers.count, 2)
        XCTAssertEqual(snapshot.providers[0], LocalAIProviderLoad(provider: .ollama, processCount: 2, cpuPercent: 25.5, residentMemoryBytes: 3_000, accelerator: LocalAIAcceleratorLoad(label: "Apple Neural Engine", utilizationPercent: nil, memoryBytes: nil)))
        XCTAssertEqual(snapshot.providers[1], LocalAIProviderLoad(provider: .lmStudio, processCount: 1, cpuPercent: 10.0, residentMemoryBytes: 4_000, accelerator: .unavailable))
    }
}

struct StaticLocalAIProcessSnapshotter: LocalAIProcessSnapshotting {
    let items: [LocalAIProcessSnapshot]

    init(snapshots: [LocalAIProcessSnapshot]) {
        self.items = snapshots
    }

    func snapshots() throws -> [LocalAIProcessSnapshot] {
        items
    }
}

struct StaticLocalAIAcceleratorSampler: LocalAIAcceleratorSampling {
    let loads: [LocalAIProvider: LocalAIAcceleratorLoad]
    func load(for provider: LocalAIProvider, processes: [LocalAIProcessSnapshot]) -> LocalAIAcceleratorLoad {
        loads[provider] ?? .unavailable
    }
}
```

- [x] **Step 2: Add monitor implementation**

Create `platforms/macos/Atlas/LocalAILoadMonitor.swift`:

```swift
import Foundation

protocol LocalAIAcceleratorSampling {
    func load(for provider: LocalAIProvider, processes: [LocalAIProcessSnapshot]) -> LocalAIAcceleratorLoad
}

struct BestEffortLocalAIAcceleratorSampler: LocalAIAcceleratorSampling {
    func load(for provider: LocalAIProvider, processes: [LocalAIProcessSnapshot]) -> LocalAIAcceleratorLoad {
        .unavailable
    }
}

struct LocalAILoadMonitor {
    let processSnapshotter: LocalAIProcessSnapshotting
    let acceleratorSampler: LocalAIAcceleratorSampling

    init(processSnapshotter: LocalAIProcessSnapshotting = LocalAIProcessSnapshotter(), acceleratorSampler: LocalAIAcceleratorSampling = BestEffortLocalAIAcceleratorSampler()) {
        self.processSnapshotter = processSnapshotter
        self.acceleratorSampler = acceleratorSampler
    }

    func snapshot(now: Date = Date()) throws -> LocalAILoadSnapshot {
        let snapshots = try processSnapshotter.snapshots()
        let grouped = Dictionary(grouping: snapshots.compactMap { snapshot -> (LocalAIProvider, LocalAIProcessSnapshot)? in
            guard let provider = Self.provider(for: snapshot) else { return nil }
            return (provider, snapshot)
        }, by: { $0.0 })

        let providerOrder: [LocalAIProvider] = [.ollama, .lmStudio]
        let loads = providerOrder.compactMap { provider -> LocalAIProviderLoad? in
            guard grouped[provider] != nil else { return nil }
            let processes = grouped[provider, default: []].map(\.1)
            return LocalAIProviderLoad(
                provider: provider,
                processCount: processes.count,
                cpuPercent: processes.reduce(0) { $0 + $1.cpuPercent },
                residentMemoryBytes: processes.reduce(0) { $0 + $1.residentMemoryBytes },
                accelerator: acceleratorSampler.load(for: provider, processes: processes)
            )
        }
        return LocalAILoadSnapshot(providers: loads, capturedAt: now)
    }

    static func provider(for snapshot: LocalAIProcessSnapshot) -> LocalAIProvider? {
        let command = snapshot.command.lowercased()
        if command.contains("ollama") {
            return .ollama
        }
        if command.contains("lm studio") || command.contains("lmstudio") {
            return .lmStudio
        }
        return nil
    }
}
```

- [x] **Step 3: Add refresh service tests with injected scheduler**

Create `platforms/macos/AtlasTests/LocalAILoadRefreshServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class LocalAILoadRefreshServiceTests: XCTestCase {
    func testStartRefreshesImmediatelyAndOnScheduledTicks() throws {
        let scheduler = ManualLocalAILoadScheduler()
        let collector = CountingLocalAILoadCollector(snapshots: [
            LocalAILoadSnapshot(providers: [], capturedAt: Date(timeIntervalSince1970: 1)),
            LocalAILoadSnapshot(providers: [LocalAIProviderLoad(provider: .ollama, processCount: 1, cpuPercent: 2, residentMemoryBytes: 3, accelerator: .unavailable)], capturedAt: Date(timeIntervalSince1970: 2)),
        ])
        var received: [LocalAILoadSnapshot] = []
        let service = LocalAILoadRefreshService(collector: collector, scheduler: scheduler, interval: 5)

        service.start { received.append($0) }
        scheduler.fire()

        XCTAssertEqual(received.map(\.capturedAt), [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 2)])
        XCTAssertEqual(scheduler.startedIntervals, [5])
    }

    func testStopCancelsScheduledRefreshes() throws {
        let scheduler = ManualLocalAILoadScheduler()
        let collector = CountingLocalAILoadCollector(snapshots: [.empty, .empty])
        var refreshCount = 0
        let service = LocalAILoadRefreshService(collector: collector, scheduler: scheduler, interval: 5)

        service.start { _ in refreshCount += 1 }
        service.stop()
        scheduler.fire()

        XCTAssertEqual(refreshCount, 1)
        XCTAssertTrue(scheduler.cancelled)
    }
}

final class ManualLocalAILoadScheduler: LocalAILoadScheduling {
    var tick: (() -> Void)?
    var startedIntervals: [TimeInterval] = []
    var cancelled = false

    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) {
        startedIntervals.append(interval)
        self.tick = tick
    }

    func cancel() {
        cancelled = true
        tick = nil
    }

    func fire() {
        tick?()
    }
}

final class CountingLocalAILoadCollector: LocalAILoadCollecting {
    var snapshots: [LocalAILoadSnapshot]

    init(snapshots: [LocalAILoadSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() throws -> LocalAILoadSnapshot {
        snapshots.removeFirst()
    }
}
```

- [x] **Step 4: Add refresh service implementation**

Create `platforms/macos/Atlas/LocalAILoadRefreshService.swift`:

```swift
import Foundation

protocol LocalAILoadCollecting {
    func snapshot() throws -> LocalAILoadSnapshot
}

extension LocalAILoadMonitor: LocalAILoadCollecting {
    func snapshot() throws -> LocalAILoadSnapshot {
        try snapshot(now: Date())
    }
}

protocol LocalAILoadScheduling {
    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void)
    func cancel()
}

final class TimerLocalAILoadScheduler: LocalAILoadScheduling {
    private var timer: Timer?

    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in tick() }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

final class LocalAILoadRefreshService {
    private let collector: LocalAILoadCollecting
    private let scheduler: LocalAILoadScheduling
    private let interval: TimeInterval

    init(collector: LocalAILoadCollecting = LocalAILoadMonitor(), scheduler: LocalAILoadScheduling = TimerLocalAILoadScheduler(), interval: TimeInterval = 5) {
        self.collector = collector
        self.scheduler = scheduler
        self.interval = interval
    }

    func start(onSnapshot: @escaping (LocalAILoadSnapshot) -> Void) {
        refresh(onSnapshot: onSnapshot)
        scheduler.schedule(every: interval) { [weak self] in
            self?.refresh(onSnapshot: onSnapshot)
        }
    }

    func stop() {
        scheduler.cancel()
    }

    private func refresh(onSnapshot: (LocalAILoadSnapshot) -> Void) {
        if let snapshot = try? collector.snapshot() {
            onSnapshot(snapshot)
        }
    }
}
```

The refresh cadence is intentionally modest: start the service only while the `ai-load-monitor` feature is enabled, refresh immediately, refresh every 5 seconds afterward, and stop the timer when the feature is disabled. Failed refreshes keep the previous snapshot visible so the panel does not flicker to empty because of one transient `ps` failure.

- [x] **Step 5: Verify monitor attribution and refresh behavior**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/LocalAILoadMonitorTests -only-testing:AtlasTests/LocalAILoadRefreshServiceTests
```

Expected: Ollama and LM Studio detection, CPU aggregation, memory aggregation, best-effort accelerator reporting, start/stop behavior, and scheduled refresh behavior pass with injected snapshots and scheduler.

## Task 4: UI Display and Feature Gating

**Files:**
- Create: `platforms/macos/Atlas/LocalAILoadPanel.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [x] **Step 1: Add AI load panel**

Create `platforms/macos/Atlas/LocalAILoadPanel.swift`:

```swift
import SwiftUI

struct LocalAILoadPanel: View {
    let snapshot: LocalAILoadSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Load").font(.subheadline).foregroundColor(.secondary)

            if snapshot.providers.isEmpty {
                Text("No local AI runtime detected").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(snapshot.providers) { provider in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.provider.title).font(.caption).fontWeight(.semibold)
                            Text("\(provider.processCount) process\(provider.processCount == 1 ? "" : "es")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(provider.cpuPercent, specifier: "%.1f")% CPU").font(.caption)
                            Text(Self.memoryString(provider.residentMemoryBytes)).font(.caption2).foregroundColor(.secondary)
                            Text(provider.accelerator.label).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    private static func memoryString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
```

- [x] **Step 2: Wire gated panel in ContentView**

In `platforms/macos/Atlas/ContentView.swift`, add state and monitor:

```swift
@State private var localAILoadSnapshot: LocalAILoadSnapshot = .empty
private let localAILoadRefreshService = LocalAILoadRefreshService()
```

Inside the main `VStack`, after `MonitoringPanel`:

```swift
if isFeatureEnabled(.aiLoadMonitor) {
    LocalAILoadPanel(snapshot: localAILoadSnapshot)

    Divider()
}
```

In `startModules()`, after the monitoring start check:

```swift
if isFeatureEnabled(.aiLoadMonitor) {
    startLocalAILoadRefresh()
}
```

In `refreshFeature(_ feature:enabled:)`, before the monitoring branch:

```swift
if feature == AtlasModule.aiLoadMonitor.featureName {
    if enabled {
        startLocalAILoadRefresh()
    } else {
        localAILoadRefreshService.stop()
        localAILoadSnapshot = .empty
    }
    return
}
```

Add:

```swift
private func startLocalAILoadRefresh() {
    localAILoadRefreshService.start { snapshot in
        DispatchQueue.main.async {
            localAILoadSnapshot = snapshot
        }
    }
}
```

If the app has a teardown hook for the menu bar panel or feature refresh lifecycle, call `localAILoadRefreshService.stop()` there as well. Do not clear the snapshot on individual refresh failures; let the refresh service keep the previous reading until the feature is disabled.

- [x] **Step 3: Verify app build**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/LocalAILoadMonitorTests -only-testing:AtlasTests/LocalAILoadRefreshServiceTests -only-testing:AtlasTests/LocalAIProcessSnapshotTests -only-testing:AtlasTests/FeatureModelsTests
```

Expected: App compiles and all local AI load tests pass after project membership is added in Task 6.

## Task 5: Xcode Project Membership

**Files:**
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Add new PBX build file entries**

Add these entries to the `PBXBuildFile` section:

```text
9B0100011A601CBA00E9B192 /* LocalAILoadModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9B0200011A601CBA00E9B192 /* LocalAILoadModels.swift */; };
9B0100021A601CBA00E9B192 /* LocalAIProcessSnapshot.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9B0200021A601CBA00E9B192 /* LocalAIProcessSnapshot.swift */; };
9B0100031A601CBA00E9B192 /* LocalAILoadMonitor.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9B0200031A601CBA00E9B192 /* LocalAILoadMonitor.swift */; };
9B0100041A601CBA00E9B192 /* LocalAILoadPanel.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9B0200041A601CBA00E9B192 /* LocalAILoadPanel.swift */; };
9B0100051A601CBA00E9B192 /* LocalAILoadMonitorTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9B0200051A601CBA00E9B192 /* LocalAILoadMonitorTests.swift */; };
9B0100061A601CBA00E9B192 /* LocalAIProcessSnapshotTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9B0200061A601CBA00E9B192 /* LocalAIProcessSnapshotTests.swift */; };
9B0100071A601CBA00E9B192 /* LocalAILoadRefreshService.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9B0200071A601CBA00E9B192 /* LocalAILoadRefreshService.swift */; };
9B0100081A601CBA00E9B192 /* LocalAILoadRefreshServiceTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9B0200081A601CBA00E9B192 /* LocalAILoadRefreshServiceTests.swift */; };
```

- [x] **Step 2: Add file references**

Add these entries to the `PBXFileReference` section:

```text
9B0200011A601CBA00E9B192 /* LocalAILoadModels.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocalAILoadModels.swift; sourceTree = "<group>"; };
9B0200021A601CBA00E9B192 /* LocalAIProcessSnapshot.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocalAIProcessSnapshot.swift; sourceTree = "<group>"; };
9B0200031A601CBA00E9B192 /* LocalAILoadMonitor.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocalAILoadMonitor.swift; sourceTree = "<group>"; };
9B0200041A601CBA00E9B192 /* LocalAILoadPanel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocalAILoadPanel.swift; sourceTree = "<group>"; };
9B0200051A601CBA00E9B192 /* LocalAILoadMonitorTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocalAILoadMonitorTests.swift; sourceTree = "<group>"; };
9B0200061A601CBA00E9B192 /* LocalAIProcessSnapshotTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocalAIProcessSnapshotTests.swift; sourceTree = "<group>"; };
9B0200071A601CBA00E9B192 /* LocalAILoadRefreshService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocalAILoadRefreshService.swift; sourceTree = "<group>"; };
9B0200081A601CBA00E9B192 /* LocalAILoadRefreshServiceTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocalAILoadRefreshServiceTests.swift; sourceTree = "<group>"; };
```

- [x] **Step 3: Add group children**

Add these app files to the `Atlas` group children list before `Assets.xcassets`:

```text
9B0200011A601CBA00E9B192 /* LocalAILoadModels.swift */,
9B0200021A601CBA00E9B192 /* LocalAIProcessSnapshot.swift */,
9B0200031A601CBA00E9B192 /* LocalAILoadMonitor.swift */,
9B0200071A601CBA00E9B192 /* LocalAILoadRefreshService.swift */,
9B0200041A601CBA00E9B192 /* LocalAILoadPanel.swift */,
```

Add these test files to the `AtlasTests` group children list:

```text
9B0200051A601CBA00E9B192 /* LocalAILoadMonitorTests.swift */,
9B0200061A601CBA00E9B192 /* LocalAIProcessSnapshotTests.swift */,
9B0200081A601CBA00E9B192 /* LocalAILoadRefreshServiceTests.swift */,
```

- [x] **Step 4: Add source phase entries**

Add these build file IDs to the `Atlas` `PBXSourcesBuildPhase` files list:

```text
9B0100011A601CBA00E9B192 /* LocalAILoadModels.swift in Sources */,
9B0100021A601CBA00E9B192 /* LocalAIProcessSnapshot.swift in Sources */,
9B0100031A601CBA00E9B192 /* LocalAILoadMonitor.swift in Sources */,
9B0100071A601CBA00E9B192 /* LocalAILoadRefreshService.swift in Sources */,
9B0100041A601CBA00E9B192 /* LocalAILoadPanel.swift in Sources */,
```

Add these build file IDs to the `AtlasTests` `PBXSourcesBuildPhase` files list:

```text
9B0100051A601CBA00E9B192 /* LocalAILoadMonitorTests.swift in Sources */,
9B0100061A601CBA00E9B192 /* LocalAIProcessSnapshotTests.swift in Sources */,
9B0100081A601CBA00E9B192 /* LocalAILoadRefreshServiceTests.swift in Sources */,
```

- [x] **Step 5: Verify project membership**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/LocalAILoadMonitorTests -only-testing:AtlasTests/LocalAILoadRefreshServiceTests -only-testing:AtlasTests/LocalAIProcessSnapshotTests -only-testing:AtlasTests/FeatureModelsTests
```

Expected: New app files compile and the local AI load test slice passes.

## Task 6: Final Verification and Commit

**Files:**
- Verify: all files changed by this plan

- [x] **Step 1: Run Rust feature tests**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
```

Expected: Pass.

- [x] **Step 2: Run local AI load XCTest slice**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/LocalAILoadMonitorTests -only-testing:AtlasTests/LocalAILoadRefreshServiceTests -only-testing:AtlasTests/LocalAIProcessSnapshotTests -only-testing:AtlasTests/FeatureModelsTests
```

Expected: Pass.

- [x] **Step 3: Review diff**

Run:

```bash
git diff -- crates/atlas-core/src/features.rs platforms/macos/Atlas platforms/macos/AtlasTests platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: Diff is limited to AI load feature registration, Swift local AI load files, Feature Center title mapping, ContentView gating, tests, and project membership.

- [x] **Step 4: Commit**

Run:

```bash
git add crates/atlas-core/src/features.rs platforms/macos/Atlas platforms/macos/AtlasTests platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add local AI load monitor"
```

Expected: Commit succeeds.

## Self-Review

1. **Spec coverage:** Ollama detection, LM Studio detection, process-level CPU and memory attribution, best-effort GPU/NPU reporting, UI display, Feature Center gating, injected process snapshot tests, and Xcode project membership are covered.
2. **Placeholder scan:** This plan contains concrete file paths, commands, and code snippets for every code change.
3. **Type consistency:** `LocalAIProvider`, `LocalAIProcessSnapshot`, `LocalAIProviderLoad`, `LocalAILoadSnapshot`, `LocalAIProcessSnapshotting`, `LocalAIAcceleratorSampling`, and `LocalAILoadMonitor` are defined before use.
