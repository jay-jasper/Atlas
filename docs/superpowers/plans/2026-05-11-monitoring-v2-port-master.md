# Monitoring v2 Port Master Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Swift monitoring mock data with real UniFFI monitoring and move Port Master into the Monitoring module.

**Architecture:** Keep Rust `atlas-ffi` as the source of truth for system monitoring and port operations. Add a small Swift service boundary that maps generated UniFFI types into existing `Monitoring...` UI models, then route `AtlasBridge` and Monitoring UI through that service so tests can inject fakes. Port Master becomes a `MonitoringPortsPanel` section inside `MonitoringPanel` instead of a separate block in `ContentView`.

**Tech Stack:** SwiftUI, XCTest, UniFFI-generated Swift bindings, Rust `atlas-core` / `atlas-ffi`, existing Xcode project.

---

## Scope Check

This plan covers only Monitoring v2 and Port Master归并:

- Replace random Swift monitoring snapshots with real UniFFI `startMonitoring` / `stopMonitoring`.
- Map generated UniFFI `SystemSnapshot` / `PortProcessInfo` into local `Monitoring...` UI models.
- Add injectable Swift monitoring service for deterministic tests.
- Move the port lookup/kill UI into Monitoring as a Ports section.
- Change the Port UI from direct PID kill to port lookup first, then kill the process returned by lookup.

This plan does not implement alerts, historical charts, thresholds, notifications, background launch agents, or a full settings screen.

## File Structure

- Modify: `platforms/macos/Atlas/SystemModels.swift`
  - Adds `Equatable` conformance to existing monitoring UI models.
  - Adds `MonitoringPortProcess`.
- Create: `platforms/macos/Atlas/MonitoringFFIMapper.swift`
  - Converts generated UniFFI `SystemSnapshot` and `PortProcessInfo` into local UI models.
- Create: `platforms/macos/Atlas/MonitoringService.swift`
  - Defines `MonitoringProviding`, `MonitoringService`, and live UniFFI callback handling.
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
  - Replaces random monitoring mock with injectable monitoring service.
  - Adds real port lookup and throwing kill methods.
- Modify: `platforms/macos/Atlas/ContentView.swift`
  - Handles throwing start/stop monitoring and removes the standalone Port Master block.
- Modify: `platforms/macos/Atlas/MonitoringPanel.swift`
  - Adds the Ports section under Monitoring.
- Modify: `platforms/macos/Atlas/PortMasterPanel.swift`
  - Replaces `PortMasterPanel` with `MonitoringPortsPanel`.
- Test: `platforms/macos/AtlasTests/MonitoringFFIMapperTests.swift`
  - Tests generated UniFFI type mapping without calling live system APIs.
- Test: `platforms/macos/AtlasTests/MonitoringServiceTests.swift`
  - Tests bridge delegation through fake monitoring provider.
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new source and test files.
- Modify: `docs/superpowers/plans/2026-05-11-monitoring-v2-port-master.md`
  - Records execution verification.

---

### Task 1: Monitoring UI Models

**Files:**
- Modify: `platforms/macos/Atlas/SystemModels.swift`

- [ ] **Step 1: Make monitoring models equatable and add port model**

Replace `platforms/macos/Atlas/SystemModels.swift` with:

```swift
import Foundation

struct MonitoringCpuCoreSnapshot: Equatable {
    let name: String
    let usage: Float
    let frequencyMhz: UInt64
}

struct MonitoringProcessSnapshot: Equatable {
    let pid: UInt32
    let name: String
    let cpuUsage: Float
    let memBytes: UInt64
}

struct MonitoringNetworkInterfaceSnapshot: Equatable {
    let name: String
    let uploadBps: UInt64
    let downloadBps: UInt64
}

struct MonitoringDiskSnapshot: Equatable {
    let name: String
    let mountPoint: String
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
}

struct MonitoringBatterySnapshot: Equatable {
    let chargePercent: Float
    let isCharging: Bool
    let timeToEmptySecs: Int64?
    let timeToFullSecs: Int64?
    let healthPercent: Float
    let cycleCount: UInt32?
}

struct MonitoringTemperatureSnapshot: Equatable {
    let label: String
    let celsius: Float
}

struct MonitoringPortProcess: Equatable {
    let port: UInt16
    let pid: UInt32
    let processName: String
}

struct MonitoringSystemSnapshot: Equatable {
    let cpuUsage: Float
    let memUsedBytes: UInt64
    let memTotalBytes: UInt64
    let netUploadBps: UInt64
    let netDownloadBps: UInt64
    let cpuCores: [MonitoringCpuCoreSnapshot]
    let memFreeBytes: UInt64
    let memAvailableBytes: UInt64
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64
    let topCpuProcesses: [MonitoringProcessSnapshot]
    let topMemProcesses: [MonitoringProcessSnapshot]
    let networkInterfaces: [MonitoringNetworkInterfaceSnapshot]
    let disks: [MonitoringDiskSnapshot]
    let battery: MonitoringBatterySnapshot?
    let temperatures: [MonitoringTemperatureSnapshot]
}

enum Formatters {
    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    static func speed(_ bps: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
    }

    static func time(_ secs: Int64) -> String {
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
```

- [ ] **Step 2: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [ ] **Step 3: Run existing macOS tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add platforms/macos/Atlas/SystemModels.swift
git commit -m "refactor(macos): make monitoring models equatable"
```

---

### Task 2: UniFFI Monitoring Mapper

**Files:**
- Create: `platforms/macos/Atlas/MonitoringFFIMapper.swift`
- Create: `platforms/macos/AtlasTests/MonitoringFFIMapperTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write mapper tests**

Create `platforms/macos/AtlasTests/MonitoringFFIMapperTests.swift`:

```swift
import XCTest
@testable import Atlas

final class MonitoringFFIMapperTests: XCTestCase {
    func testMapsSystemSnapshot() {
        let ffiSnapshot = SystemSnapshot(
            cpuUsage: 42.5,
            memUsedBytes: 6_000,
            memTotalBytes: 10_000,
            netUploadBps: 100,
            netDownloadBps: 200,
            cpuCores: [
                CpuCoreSnapshot(name: "cpu0", usage: 10.5, frequencyMhz: 3200)
            ],
            memFreeBytes: 1_000,
            memAvailableBytes: 3_000,
            swapUsedBytes: 128,
            swapTotalBytes: 256,
            topCpuProcesses: [
                ProcessSnapshot(pid: 11, name: "CPU", cpuUsage: 21.5, memBytes: 900)
            ],
            topMemProcesses: [
                ProcessSnapshot(pid: 12, name: "MEM", cpuUsage: 2.5, memBytes: 1_200)
            ],
            networkInterfaces: [
                NetworkInterfaceSnapshot(name: "en0", uploadBps: 10, downloadBps: 20)
            ],
            disks: [
                DiskSnapshot(name: "Macintosh HD", mountPoint: "/", totalBytes: 100, usedBytes: 40, availableBytes: 60)
            ],
            battery: BatterySnapshot(
                chargePercent: 77,
                isCharging: true,
                timeToEmptySecs: nil,
                timeToFullSecs: 1200,
                healthPercent: 95,
                cycleCount: 123
            ),
            temperatures: [
                TemperatureSnapshot(label: "CPU", celsius: 55)
            ]
        )

        let snapshot = MonitoringFFIMapper.map(snapshot: ffiSnapshot)

        XCTAssertEqual(snapshot.cpuUsage, 42.5)
        XCTAssertEqual(snapshot.memUsedBytes, 6_000)
        XCTAssertEqual(snapshot.memTotalBytes, 10_000)
        XCTAssertEqual(snapshot.cpuCores, [
            MonitoringCpuCoreSnapshot(name: "cpu0", usage: 10.5, frequencyMhz: 3200)
        ])
        XCTAssertEqual(snapshot.topCpuProcesses, [
            MonitoringProcessSnapshot(pid: 11, name: "CPU", cpuUsage: 21.5, memBytes: 900)
        ])
        XCTAssertEqual(snapshot.networkInterfaces, [
            MonitoringNetworkInterfaceSnapshot(name: "en0", uploadBps: 10, downloadBps: 20)
        ])
        XCTAssertEqual(snapshot.disks, [
            MonitoringDiskSnapshot(name: "Macintosh HD", mountPoint: "/", totalBytes: 100, usedBytes: 40, availableBytes: 60)
        ])
        XCTAssertEqual(snapshot.battery, MonitoringBatterySnapshot(
            chargePercent: 77,
            isCharging: true,
            timeToEmptySecs: nil,
            timeToFullSecs: 1200,
            healthPercent: 95,
            cycleCount: 123
        ))
        XCTAssertEqual(snapshot.temperatures, [
            MonitoringTemperatureSnapshot(label: "CPU", celsius: 55)
        ])
    }

    func testMapsPortProcess() {
        let info = PortProcessInfo(port: 3000, pid: 42, processName: "node")

        let mapped = MonitoringFFIMapper.map(port: info)

        XCTAssertEqual(mapped, MonitoringPortProcess(port: 3000, pid: 42, processName: "node"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/MonitoringFFIMapperTests
```

Expected: FAIL because `MonitoringFFIMapper` does not exist or the test file is not in the project yet.

- [ ] **Step 3: Add mapper implementation**

Create `platforms/macos/Atlas/MonitoringFFIMapper.swift`:

```swift
enum MonitoringFFIMapper {
    static func map(snapshot: SystemSnapshot) -> MonitoringSystemSnapshot {
        MonitoringSystemSnapshot(
            cpuUsage: snapshot.cpuUsage,
            memUsedBytes: snapshot.memUsedBytes,
            memTotalBytes: snapshot.memTotalBytes,
            netUploadBps: snapshot.netUploadBps,
            netDownloadBps: snapshot.netDownloadBps,
            cpuCores: snapshot.cpuCores.map {
                MonitoringCpuCoreSnapshot(name: $0.name, usage: $0.usage, frequencyMhz: $0.frequencyMhz)
            },
            memFreeBytes: snapshot.memFreeBytes,
            memAvailableBytes: snapshot.memAvailableBytes,
            swapUsedBytes: snapshot.swapUsedBytes,
            swapTotalBytes: snapshot.swapTotalBytes,
            topCpuProcesses: snapshot.topCpuProcesses.map {
                MonitoringProcessSnapshot(pid: $0.pid, name: $0.name, cpuUsage: $0.cpuUsage, memBytes: $0.memBytes)
            },
            topMemProcesses: snapshot.topMemProcesses.map {
                MonitoringProcessSnapshot(pid: $0.pid, name: $0.name, cpuUsage: $0.cpuUsage, memBytes: $0.memBytes)
            },
            networkInterfaces: snapshot.networkInterfaces.map {
                MonitoringNetworkInterfaceSnapshot(name: $0.name, uploadBps: $0.uploadBps, downloadBps: $0.downloadBps)
            },
            disks: snapshot.disks.map {
                MonitoringDiskSnapshot(
                    name: $0.name,
                    mountPoint: $0.mountPoint,
                    totalBytes: $0.totalBytes,
                    usedBytes: $0.usedBytes,
                    availableBytes: $0.availableBytes
                )
            },
            battery: snapshot.battery.map {
                MonitoringBatterySnapshot(
                    chargePercent: $0.chargePercent,
                    isCharging: $0.isCharging,
                    timeToEmptySecs: $0.timeToEmptySecs,
                    timeToFullSecs: $0.timeToFullSecs,
                    healthPercent: $0.healthPercent,
                    cycleCount: $0.cycleCount
                )
            },
            temperatures: snapshot.temperatures.map {
                MonitoringTemperatureSnapshot(label: $0.label, celsius: $0.celsius)
            }
        )
    }

    static func map(port: PortProcessInfo) -> MonitoringPortProcess {
        MonitoringPortProcess(
            port: port.port,
            pid: port.pid,
            processName: port.processName
        )
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so:

- `MonitoringFFIMapper.swift` is in `Atlas` target Sources.
- `MonitoringFFIMapperTests.swift` is in `AtlasTests` target Sources.

- [ ] **Step 5: Run mapper tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/MonitoringFFIMapperTests
```

Expected: PASS, 2 tests.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/MonitoringFFIMapper.swift \
  platforms/macos/AtlasTests/MonitoringFFIMapperTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): map uniffi monitoring models"
```

---

### Task 3: Monitoring Service Boundary

**Files:**
- Create: `platforms/macos/Atlas/MonitoringService.swift`
- Create: `platforms/macos/AtlasTests/MonitoringServiceTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write service tests**

Create `platforms/macos/AtlasTests/MonitoringServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

private enum MonitoringServiceTestError: LocalizedError {
    case denied

    var errorDescription: String? {
        "denied"
    }
}

final class MonitoringServiceTests: XCTestCase {
    func testInjectedStartFunctionReceivesCallback() throws {
        let expected = MonitoringSystemSnapshot.testFixture()
        var received: MonitoringSystemSnapshot?
        let service = MonitoringService(
            startMonitoring: { callback in
                callback(expected)
            },
            stopMonitoring: {},
            lookupPort: { _ in nil },
            killPortProcess: { _ in false }
        )

        try service.startMonitoring { snapshot in
            received = snapshot
        }

        XCTAssertEqual(received, expected)
    }

    func testInjectedPortLookupAndKill() throws {
        let expected = MonitoringPortProcess(port: 3000, pid: 99, processName: "node")
        var killedPID: UInt32?
        let service = MonitoringService(
            startMonitoring: { _ in },
            stopMonitoring: {},
            lookupPort: { port in
                XCTAssertEqual(port, 3000)
                return expected
            },
            killPortProcess: { pid in
                killedPID = pid
                return true
            }
        )

        let info = try service.lookupPort(3000)
        let killed = try service.killPortProcess(99)

        XCTAssertEqual(info, expected)
        XCTAssertEqual(killedPID, 99)
        XCTAssertTrue(killed)
    }

    func testInjectedErrorsPropagateLocalizedMessage() {
        let service = MonitoringService(
            startMonitoring: { _ in throw MonitoringServiceTestError.denied },
            stopMonitoring: {},
            lookupPort: { _ in nil },
            killPortProcess: { _ in false }
        )

        XCTAssertThrowsError(try service.startMonitoring { _ in }) { error in
            XCTAssertEqual(error.localizedDescription, "denied")
        }
    }
}

private extension MonitoringSystemSnapshot {
    static func testFixture() -> MonitoringSystemSnapshot {
        MonitoringSystemSnapshot(
            cpuUsage: 12,
            memUsedBytes: 100,
            memTotalBytes: 200,
            netUploadBps: 3,
            netDownloadBps: 4,
            cpuCores: [MonitoringCpuCoreSnapshot(name: "cpu0", usage: 12, frequencyMhz: 3000)],
            memFreeBytes: 50,
            memAvailableBytes: 80,
            swapUsedBytes: 1,
            swapTotalBytes: 2,
            topCpuProcesses: [MonitoringProcessSnapshot(pid: 1, name: "A", cpuUsage: 2, memBytes: 3)],
            topMemProcesses: [MonitoringProcessSnapshot(pid: 2, name: "B", cpuUsage: 4, memBytes: 5)],
            networkInterfaces: [MonitoringNetworkInterfaceSnapshot(name: "en0", uploadBps: 6, downloadBps: 7)],
            disks: [MonitoringDiskSnapshot(name: "Disk", mountPoint: "/", totalBytes: 8, usedBytes: 4, availableBytes: 4)],
            battery: nil,
            temperatures: []
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/MonitoringServiceTests
```

Expected: FAIL because `MonitoringService` does not exist or the test file is not in the project yet.

- [ ] **Step 3: Add service implementation**

Create `platforms/macos/Atlas/MonitoringService.swift`:

```swift
import Foundation

protocol MonitoringProviding {
    func startMonitoring(callback: @escaping (MonitoringSystemSnapshot) -> Void) throws
    func stopMonitoring() throws
    func lookupPort(_ port: UInt16) throws -> MonitoringPortProcess?
    func killPortProcess(_ pid: UInt32) throws -> Bool
}

struct MonitoringService: MonitoringProviding {
    var startMonitoring: (@escaping (MonitoringSystemSnapshot) -> Void) throws -> Void
    var stopMonitoring: () throws -> Void
    var lookupPort: (UInt16) throws -> MonitoringPortProcess?
    var killPortProcess: (UInt32) throws -> Bool

    func startMonitoring(callback: @escaping (MonitoringSystemSnapshot) -> Void) throws {
        try startMonitoring(callback)
    }

    func stopMonitoring() throws {
        try stopMonitoring()
    }

    func lookupPort(_ port: UInt16) throws -> MonitoringPortProcess? {
        try lookupPort(port)
    }

    func killPortProcess(_ pid: UInt32) throws -> Bool {
        try killPortProcess(pid)
    }
}

private final class AtlasSystemMonitorCallback: SystemMonitorCallback {
    private let callback: (MonitoringSystemSnapshot) -> Void

    init(callback: @escaping (MonitoringSystemSnapshot) -> Void) {
        self.callback = callback
    }

    func onSnapshot(snapshot: SystemSnapshot) {
        callback(MonitoringFFIMapper.map(snapshot: snapshot))
    }
}

extension MonitoringService {
    static let live = MonitoringService(
        startMonitoring: { callback in
            try Atlas.startMonitoring(callback: AtlasSystemMonitorCallback(callback: callback))
        },
        stopMonitoring: {
            try Atlas.stopMonitoring()
        },
        lookupPort: { port in
            try Atlas.lookupPort(port: port).map(MonitoringFFIMapper.map(port:))
        },
        killPortProcess: { pid in
            try Atlas.killPortProcess(pid: pid)
        }
    )
}
```

- [ ] **Step 4: Add files to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so:

- `MonitoringService.swift` is in `Atlas` target Sources.
- `MonitoringServiceTests.swift` is in `AtlasTests` target Sources.

- [ ] **Step 5: Run service tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/MonitoringServiceTests
```

Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/MonitoringService.swift \
  platforms/macos/AtlasTests/MonitoringServiceTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add monitoring service boundary"
```

---

### Task 4: AtlasBridge Monitoring Routing

**Files:**
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
- Create: `platforms/macos/AtlasTests/AtlasBridgeMonitoringTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write bridge tests**

Create `platforms/macos/AtlasTests/AtlasBridgeMonitoringTests.swift`:

```swift
import XCTest
@testable import Atlas

private final class FakeMonitoringProvider: MonitoringProviding {
    var startCount = 0
    var stopCount = 0
    var callbackSnapshot = MonitoringSystemSnapshot.testFixture()
    var lookedUpPort: UInt16?
    var killedPID: UInt32?
    var lookupResult: MonitoringPortProcess?
    var killResult = true

    func startMonitoring(callback: @escaping (MonitoringSystemSnapshot) -> Void) throws {
        startCount += 1
        callback(callbackSnapshot)
    }

    func stopMonitoring() throws {
        stopCount += 1
    }

    func lookupPort(_ port: UInt16) throws -> MonitoringPortProcess? {
        lookedUpPort = port
        return lookupResult
    }

    func killPortProcess(_ pid: UInt32) throws -> Bool {
        killedPID = pid
        return killResult
    }
}

final class AtlasBridgeMonitoringTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.monitoringService = .live
        super.tearDown()
    }

    func testStartMonitoringUsesProvider() throws {
        let provider = FakeMonitoringProvider()
        AtlasBridge.monitoringService = provider
        var received: MonitoringSystemSnapshot?

        try AtlasBridge.startMonitoring { snapshot in
            received = snapshot
        }

        XCTAssertEqual(provider.startCount, 1)
        XCTAssertEqual(received, provider.callbackSnapshot)
    }

    func testStopMonitoringUsesProvider() throws {
        let provider = FakeMonitoringProvider()
        AtlasBridge.monitoringService = provider

        try AtlasBridge.stopMonitoring()

        XCTAssertEqual(provider.stopCount, 1)
    }

    func testLookupAndKillUseProvider() throws {
        let provider = FakeMonitoringProvider()
        provider.lookupResult = MonitoringPortProcess(port: 3000, pid: 44, processName: "node")
        AtlasBridge.monitoringService = provider

        let lookup = try AtlasBridge.lookupPort(3000)
        let killed = try AtlasBridge.killPortProcess(pid: 44)

        XCTAssertEqual(provider.lookedUpPort, 3000)
        XCTAssertEqual(lookup, MonitoringPortProcess(port: 3000, pid: 44, processName: "node"))
        XCTAssertEqual(provider.killedPID, 44)
        XCTAssertTrue(killed)
    }
}

private extension MonitoringSystemSnapshot {
    static func testFixture() -> MonitoringSystemSnapshot {
        MonitoringSystemSnapshot(
            cpuUsage: 1,
            memUsedBytes: 2,
            memTotalBytes: 3,
            netUploadBps: 4,
            netDownloadBps: 5,
            cpuCores: [],
            memFreeBytes: 6,
            memAvailableBytes: 7,
            swapUsedBytes: 8,
            swapTotalBytes: 9,
            topCpuProcesses: [],
            topMemProcesses: [],
            networkInterfaces: [],
            disks: [],
            battery: nil,
            temperatures: []
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/AtlasBridgeMonitoringTests
```

Expected: FAIL because `AtlasBridge.monitoringService` and throwing bridge methods do not exist.

- [ ] **Step 3: Replace monitoring mock in `AtlasBridge`**

In `platforms/macos/Atlas/AtlasBridge.swift`, remove:

```swift
static var monitoringTimer: Timer?
```

Add this static property near the other injectable services:

```swift
static var monitoringService: MonitoringProviding = MonitoringService.live
```

Replace the existing random `startMonitoring(callback:)`, `stopMonitoring()`, and `killPortProcess(pid:)` methods with:

```swift
static func startMonitoring(callback: @escaping (MonitoringSystemSnapshot) -> Void) throws {
    try monitoringService.startMonitoring(callback: callback)
}

static func stopMonitoring() throws {
    try monitoringService.stopMonitoring()
}

static func lookupPort(_ port: UInt16) throws -> MonitoringPortProcess? {
    try monitoringService.lookupPort(port)
}

static func killPortProcess(pid: UInt32) throws -> Bool {
    try monitoringService.killPortProcess(pid)
}
```

Do not change screenshot or window capture methods in this task.

- [ ] **Step 4: Add test file to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `AtlasBridgeMonitoringTests.swift` is in `AtlasTests` target Sources.

- [ ] **Step 5: Run bridge monitoring tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/AtlasBridgeMonitoringTests
```

Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/AtlasBridge.swift \
  platforms/macos/AtlasTests/AtlasBridgeMonitoringTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): route monitoring through service"
```

---

### Task 5: ContentView Monitoring Error Handling

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Update stop handling**

In `platforms/macos/Atlas/ContentView.swift`, replace:

```swift
private func stopModules() {
    AtlasBridge.stopMonitoring()
}
```

with:

```swift
private func stopModules() {
    do {
        try AtlasBridge.stopMonitoring()
    } catch {
        showStatus(error.localizedDescription, kind: .error)
    }
}
```

- [ ] **Step 2: Update feature disable handling**

In `handleFeatureChange(_:enabled:)`, replace:

```swift
AtlasBridge.stopMonitoring()
snapshot = nil
```

with:

```swift
do {
    try AtlasBridge.stopMonitoring()
    snapshot = nil
} catch {
    showStatus(error.localizedDescription, kind: .error)
}
```

- [ ] **Step 3: Update `startMonitoring()`**

Replace the existing `startMonitoring()` method with:

```swift
private func startMonitoring() {
    do {
        try AtlasBridge.startMonitoring { snapshot in
            DispatchQueue.main.async {
                self.snapshot = snapshot
            }
        }
    } catch {
        showStatus(error.localizedDescription, kind: .error)
    }
}
```

- [ ] **Step 4: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [ ] **Step 5: Build app**

Run:

```bash
xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/ContentView.swift
git commit -m "fix(macos): handle monitoring service errors"
```

---

### Task 6: Monitoring Ports Panel

**Files:**
- Modify: `platforms/macos/Atlas/PortMasterPanel.swift`
- Modify: `platforms/macos/Atlas/MonitoringPanel.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Replace Port Master UI with Monitoring Ports section**

Replace `platforms/macos/Atlas/PortMasterPanel.swift` with:

```swift
import SwiftUI

struct MonitoringPortsPanel: View {
    @State private var portInput: String = ""
    @State private var lookupResult: MonitoringPortProcess?
    @State private var portStatus: String = ""
    @State private var isError: Bool = false

    var body: some View {
        Group {
            Text("Ports").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Port", text: $portInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Lookup", action: lookupPort)
                        .disabled(portInput.isEmpty)
                }

                if let lookupResult {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(lookupResult.processName) (\(lookupResult.pid))")
                            .font(.caption)
                        Text("Listening on port \(lookupResult.port)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Kill Process", role: .destructive, action: killProcess)
                            .buttonStyle(.bordered)
                    }
                }

                if !portStatus.isEmpty {
                    Text(portStatus)
                        .font(.caption)
                        .foregroundColor(isError ? .red : .secondary)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func lookupPort() {
        guard let port = UInt16(portInput) else {
            lookupResult = nil
            portStatus = "Invalid port: \(portInput)"
            isError = true
            return
        }

        do {
            let result = try AtlasBridge.lookupPort(port)
            lookupResult = result
            if let result {
                portStatus = "Found \(result.processName)"
                isError = false
            } else {
                portStatus = "No process is listening on port \(port)"
                isError = false
            }
        } catch {
            lookupResult = nil
            portStatus = error.localizedDescription
            isError = true
        }
    }

    private func killProcess() {
        guard let lookupResult else { return }

        do {
            if try AtlasBridge.killPortProcess(pid: lookupResult.pid) {
                portStatus = "Killed \(lookupResult.processName)"
                portInput = ""
                self.lookupResult = nil
                isError = false
            } else {
                portStatus = "Failed to kill \(lookupResult.processName)"
                isError = true
            }
        } catch {
            portStatus = error.localizedDescription
            isError = true
        }
    }
}
```

- [ ] **Step 2: Add ports section to MonitoringPanel**

In `platforms/macos/Atlas/MonitoringPanel.swift`, add a ports section after `processSection(snapshot)`:

```swift
Divider()
MonitoringPortsPanel()
```

The end of the non-loading body should read:

```swift
Divider()
processSection(snapshot)
Divider()
MonitoringPortsPanel()
```

- [ ] **Step 3: Remove standalone Port Master from ContentView**

In `platforms/macos/Atlas/ContentView.swift`, remove this block:

```swift
Divider()

PortMasterPanel()

Divider()
```

Monitoring should now contain the Ports section internally.

- [ ] **Step 4: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [ ] **Step 5: Run relevant tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' \
  -only-testing:AtlasTests/AtlasBridgeMonitoringTests \
  -only-testing:AtlasTests/MonitoringServiceTests \
  -only-testing:AtlasTests/MonitoringFFIMapperTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/PortMasterPanel.swift \
  platforms/macos/Atlas/MonitoringPanel.swift \
  platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): move port master into monitoring"
```

---

### Task 7: Verification Notes

**Files:**
- Modify: `docs/superpowers/plans/2026-05-11-monitoring-v2-port-master.md`

- [ ] **Step 1: Run Rust tests**

Run:

```bash
cargo test -p atlas-core -p atlas-ffi
```

Expected: PASS.

- [ ] **Step 2: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [ ] **Step 3: Run Xcode build**

Run:

```bash
xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run full Xcode tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-11-monitoring-v2-port-master.md`:

```markdown
## Execution Verification Notes

- Rust:
  - `cargo test -p atlas-core -p atlas-ffi`
  - Result: PASS
- Swift parse:
  - `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - Result: PASS
- Xcode:
  - `xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build`
  - Result: PASS
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: PASS
- Manual:
  - Manual monitoring and port kill verification was not performed. On 2026-05-11, user acceptance criteria for these task plans is automated/unit tests passing.
- Remaining limitations:
  - Port kill still calls the existing Rust implementation, which uses `kill -9`.
  - Monitoring callback delivery depends on the UniFFI callback thread and dispatches to the main queue in `ContentView`.
```

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-05-11-monitoring-v2-port-master.md
git commit -m "docs: record monitoring v2 verification"
```

---

## Self-Review

1. **Spec coverage:** The plan replaces Swift random monitoring with real UniFFI monitoring, adds deterministic service injection, maps generated FFI types into local UI types, and moves Port Master under Monitoring as a Ports section.
2. **Placeholder scan:** The plan contains concrete file paths, code, commands, and expected outcomes. Manual verification is explicitly waived based on the user's 2026-05-11 instruction and is not represented as performed.
3. **Type consistency:** `MonitoringPortProcess`, `MonitoringFFIMapper`, `MonitoringProviding`, `MonitoringService`, `AtlasBridge.lookupPort(_:)`, `AtlasBridge.killPortProcess(pid:)`, and `MonitoringPortsPanel` are defined before they are referenced by later tasks.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-11-monitoring-v2-port-master.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

## Execution Verification Notes

- Rust:
  - `cargo test -p atlas-core -p atlas-ffi`
  - Result: PASS
  - Summary: `atlas-core` ran 18 tests, `atlas-ffi` ran 4 tests, and doc tests ran with 0 failures.
- Swift parse:
  - `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - Result: PASS
- Xcode:
  - `xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build`
  - Result: PASS
  - Summary: `** BUILD SUCCEEDED **`
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: PASS
  - Summary: `AtlasTests.xctest` ran 38 tests with 0 failures; `** TEST SUCCEEDED **`
- Manual:
  - Manual monitoring and port kill verification was not performed. On 2026-05-11, user acceptance criteria for these task plans is automated/unit tests passing.
- Remaining limitations:
  - Port kill still calls the existing Rust implementation, which uses `kill -9`.
  - Monitoring callback delivery depends on the UniFFI callback thread and dispatches to the main queue in `ContentView`.
