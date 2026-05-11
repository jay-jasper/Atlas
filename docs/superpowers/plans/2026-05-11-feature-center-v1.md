# Feature Center v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Swift-side feature toggle mocks with the real UniFFI feature manager and split feature selection into a focused Feature Center panel.

**Architecture:** Rust `FeatureManager` and `atlas-ffi` already expose `listFeatures()` and `toggleFeature(name:enabled:)`; Swift should treat those as the source of truth. Add a small Swift feature service and local UI model, route `AtlasBridge` through that service for test injection, then update `ContentView` so enabled modules are shown from real feature state. Keep this slice local and in-memory; persistence and a separate Settings window are later work.

**Tech Stack:** SwiftUI, XCTest, UniFFI-generated Swift bindings, Rust `atlas-core` / `atlas-ffi`, existing Xcode project.

---

## Scope Check

This plan covers Feature Center v1 only:

- Replace `AtlasBridge.listFeatures()` mock with real UniFFI-backed feature entries.
- Replace `AtlasBridge.toggleFeature(name:enabled:)` print mock with real UniFFI-backed toggling.
- Add deterministic Swift tests through an injectable `FeatureProviding` service.
- Split the feature toggle UI into a focused `FeatureCenterPanel`.
- Make `ContentView` initialize modules from real enabled/disabled feature state.
- Keep `port-master` under `monitoring`; do not add a separate Port Master toggle.

This plan does not implement persisted user preferences, launch-at-login, a detached Settings window, hotkeys, OCR, translation, per-subfeature paid gating, or feature dependency resolution.

## File Structure

- Create: `platforms/macos/Atlas/FeatureModels.swift`
  - Local `AtlasFeature` UI model.
  - `AtlasFeatureMapper` that maps generated UniFFI `FeatureEntry` into `AtlasFeature`.
  - Stable display title helper for known features.
- Create: `platforms/macos/Atlas/FeatureService.swift`
  - `FeatureProviding` protocol.
  - `FeatureService` closure-backed implementation.
  - `.live` implementation that calls UniFFI `Atlas.listFeatures()` / `Atlas.toggleFeature(name:enabled:)`.
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
  - Add injectable `featureService`.
  - Replace mock feature methods with throwing methods returning local `AtlasFeature`.
- Modify: `platforms/macos/Atlas/FeatureTogglePanel.swift`
  - Replace `FeatureTogglePanel` with `FeatureCenterPanel`.
  - Accept `[AtlasFeature]` and a binding dictionary keyed by feature name.
- Modify: `platforms/macos/Atlas/ContentView.swift`
  - Load feature state from `AtlasBridge.listFeatures()`.
  - Stop defaulting all features to enabled.
  - Handle feature list/toggle errors.
  - Keep only enabled modules visible.
  - Keep Ports inside Monitoring only.
- Test: `platforms/macos/AtlasTests/FeatureModelsTests.swift`
  - Tests UniFFI feature mapping and display titles.
- Test: `platforms/macos/AtlasTests/FeatureServiceTests.swift`
  - Tests injected service closures and error propagation.
- Test: `platforms/macos/AtlasTests/AtlasBridgeFeatureTests.swift`
  - Tests `AtlasBridge` delegates feature list/toggle through `FeatureProviding`.
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new source and test files to Xcode targets.
- Modify: `docs/superpowers/plans/2026-05-11-feature-center-v1.md`
  - Records execution verification after implementation.

---

### Task 1: Feature UI Models

**Files:**
- Create: `platforms/macos/Atlas/FeatureModels.swift`
- Create: `platforms/macos/AtlasTests/FeatureModelsTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write feature model tests**

Create `platforms/macos/AtlasTests/FeatureModelsTests.swift`:

```swift
import XCTest
@testable import Atlas

final class FeatureModelsTests: XCTestCase {
    func testMapsEnabledFeatureEntry() {
        let entry = FeatureEntry(name: "monitoring", status: .enabled)

        let feature = AtlasFeatureMapper.map(entry)

        XCTAssertEqual(feature, AtlasFeature(name: "monitoring", isEnabled: true))
        XCTAssertEqual(feature.id, "monitoring")
        XCTAssertEqual(feature.title, "Monitoring")
    }

    func testMapsDisabledFeatureEntry() {
        let entry = FeatureEntry(name: "screenshot", status: .disabled)

        let feature = AtlasFeatureMapper.map(entry)

        XCTAssertEqual(feature, AtlasFeature(name: "screenshot", isEnabled: false))
        XCTAssertEqual(feature.title, "Screenshot")
    }

    func testFormatsUnknownFeatureName() {
        let feature = AtlasFeature(name: "window-manager", isEnabled: false)

        XCTAssertEqual(feature.title, "Window Manager")
    }
}
```

- [ ] **Step 2: Run model tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FeatureModelsTests
```

Expected: FAIL because `FeatureModelsTests.swift` is not in the Xcode project yet or `AtlasFeature` does not exist.

- [ ] **Step 3: Add feature model implementation**

Create `platforms/macos/Atlas/FeatureModels.swift`:

```swift
import Foundation

struct AtlasFeature: Identifiable, Equatable {
    let name: String
    let isEnabled: Bool

    var id: String { name }

    var title: String {
        AtlasFeatureTitles.title(for: name)
    }
}

enum AtlasFeatureMapper {
    static func map(_ entry: FeatureEntry) -> AtlasFeature {
        AtlasFeature(
            name: entry.name,
            isEnabled: entry.status == .enabled
        )
    }
}

private enum AtlasFeatureTitles {
    static func title(for name: String) -> String {
        switch name {
        case AtlasModule.monitoring.featureName:
            return AtlasModule.monitoring.title
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

- [ ] **Step 4: Add files to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so:

- `FeatureModels.swift` is in the `Atlas` target Sources.
- `FeatureModelsTests.swift` is in the `AtlasTests` target Sources.

- [ ] **Step 5: Run model tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FeatureModelsTests
```

Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/FeatureModels.swift \
  platforms/macos/AtlasTests/FeatureModelsTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add feature ui models"
```

---

### Task 2: Feature Service Boundary

**Files:**
- Create: `platforms/macos/Atlas/FeatureService.swift`
- Create: `platforms/macos/AtlasTests/FeatureServiceTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write service tests**

Create `platforms/macos/AtlasTests/FeatureServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class FeatureServiceTests: XCTestCase {
    func testInjectedListFeaturesReturnsFeatures() throws {
        let expected = [
            AtlasFeature(name: "monitoring", isEnabled: true),
            AtlasFeature(name: "screenshot", isEnabled: false)
        ]
        let service = FeatureService(
            listFeatures: { expected },
            toggleFeature: { _, _ in true }
        )

        XCTAssertEqual(try service.listFeatures(), expected)
    }

    func testInjectedToggleReceivesArgumentsAndReturnsResult() throws {
        var receivedName: String?
        var receivedEnabled: Bool?
        let service = FeatureService(
            listFeatures: { [] },
            toggleFeature: { name, enabled in
                receivedName = name
                receivedEnabled = enabled
                return true
            }
        )

        let didToggle = try service.toggleFeature(name: "monitoring", enabled: true)

        XCTAssertTrue(didToggle)
        XCTAssertEqual(receivedName, "monitoring")
        XCTAssertEqual(receivedEnabled, true)
    }

    func testInjectedErrorsPropagateLocalizedMessage() {
        let service = FeatureService(
            listFeatures: { throw FeatureServiceTestError.denied },
            toggleFeature: { _, _ in true }
        )

        XCTAssertThrowsError(try service.listFeatures()) { error in
            XCTAssertEqual(error.localizedDescription, "denied")
        }
    }
}

private enum FeatureServiceTestError: LocalizedError {
    case denied

    var errorDescription: String? {
        switch self {
        case .denied:
            return "denied"
        }
    }
}
```

- [ ] **Step 2: Run service tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FeatureServiceTests
```

Expected: FAIL because `FeatureService` does not exist or the test file is not in the Xcode project yet.

- [ ] **Step 3: Add service implementation**

Create `platforms/macos/Atlas/FeatureService.swift`:

```swift
import Foundation

protocol FeatureProviding {
    func listFeatures() throws -> [AtlasFeature]
    func toggleFeature(name: String, enabled: Bool) throws -> Bool
}

struct FeatureService: FeatureProviding {
    private let listFeaturesHandler: () throws -> [AtlasFeature]
    private let toggleFeatureHandler: (String, Bool) throws -> Bool

    init(
        listFeatures: @escaping () throws -> [AtlasFeature],
        toggleFeature: @escaping (String, Bool) throws -> Bool
    ) {
        self.listFeaturesHandler = listFeatures
        self.toggleFeatureHandler = toggleFeature
    }

    func listFeatures() throws -> [AtlasFeature] {
        try listFeaturesHandler()
    }

    func toggleFeature(name: String, enabled: Bool) throws -> Bool {
        try toggleFeatureHandler(name, enabled)
    }
}

extension FeatureService {
    static let live = FeatureService(
        listFeatures: {
            try Atlas.listFeatures().map(AtlasFeatureMapper.map)
        },
        toggleFeature: { name, enabled in
            try Atlas.toggleFeature(name: name, enabled: enabled)
        }
    )
}
```

- [ ] **Step 4: Add files to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so:

- `FeatureService.swift` is in the `Atlas` target Sources.
- `FeatureServiceTests.swift` is in the `AtlasTests` target Sources.

- [ ] **Step 5: Run service tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FeatureServiceTests
```

Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/FeatureService.swift \
  platforms/macos/AtlasTests/FeatureServiceTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add feature service boundary"
```

---

### Task 3: AtlasBridge Feature Routing

**Files:**
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
- Create: `platforms/macos/AtlasTests/AtlasBridgeFeatureTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write bridge tests**

Create `platforms/macos/AtlasTests/AtlasBridgeFeatureTests.swift`:

```swift
import XCTest
@testable import Atlas

private extension FeatureProviding where Self == FeatureService {
    static var live: FeatureService { FeatureService.live }
}

private final class FakeFeatureProvider: FeatureProviding {
    var features: [AtlasFeature] = []
    var listCount = 0
    var toggledName: String?
    var toggledEnabled: Bool?
    var toggleResult = true

    func listFeatures() throws -> [AtlasFeature] {
        listCount += 1
        return features
    }

    func toggleFeature(name: String, enabled: Bool) throws -> Bool {
        toggledName = name
        toggledEnabled = enabled
        return toggleResult
    }
}

final class AtlasBridgeFeatureTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.featureService = .live
        super.tearDown()
    }

    func testListFeaturesUsesProvider() throws {
        let provider = FakeFeatureProvider()
        provider.features = [
            AtlasFeature(name: "monitoring", isEnabled: true),
            AtlasFeature(name: "screenshot", isEnabled: false)
        ]
        AtlasBridge.featureService = provider

        let features = try AtlasBridge.listFeatures()

        XCTAssertEqual(provider.listCount, 1)
        XCTAssertEqual(features, provider.features)
    }

    func testToggleFeatureUsesProvider() throws {
        let provider = FakeFeatureProvider()
        AtlasBridge.featureService = provider

        let result = try AtlasBridge.toggleFeature(name: "monitoring", enabled: true)

        XCTAssertTrue(result)
        XCTAssertEqual(provider.toggledName, "monitoring")
        XCTAssertEqual(provider.toggledEnabled, true)
    }

    func testToggleFeatureCanReturnFalseForUnknownFeature() throws {
        let provider = FakeFeatureProvider()
        provider.toggleResult = false
        AtlasBridge.featureService = provider

        let result = try AtlasBridge.toggleFeature(name: "unknown", enabled: true)

        XCTAssertFalse(result)
    }
}
```

- [ ] **Step 2: Run bridge tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/AtlasBridgeFeatureTests
```

Expected: FAIL because `AtlasBridge.featureService` and throwing feature methods do not exist or the test file is not in the project yet.

- [ ] **Step 3: Replace feature mock in AtlasBridge**

In `platforms/macos/Atlas/AtlasBridge.swift`, add this static property near `captureService` and `monitoringService`:

```swift
static var featureService: FeatureProviding = FeatureService.live
```

Replace:

```swift
static func listFeatures() -> [String] {
    return AtlasModule.allCases.map(\.featureName)
}

static func toggleFeature(name: String, enabled: Bool) {
    print("Feature \(name) toggled to \(enabled)")
}
```

with:

```swift
static func listFeatures() throws -> [AtlasFeature] {
    try featureService.listFeatures()
}

static func toggleFeature(name: String, enabled: Bool) throws -> Bool {
    try featureService.toggleFeature(name: name, enabled: enabled)
}
```

Do not change screenshot, window capture, or monitoring methods in this task.

- [ ] **Step 4: Add test file to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `AtlasBridgeFeatureTests.swift` is in the `AtlasTests` target Sources.

- [ ] **Step 5: Run bridge tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/AtlasBridgeFeatureTests
```

Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/AtlasBridge.swift \
  platforms/macos/AtlasTests/AtlasBridgeFeatureTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): route features through service"
```

---

### Task 4: Feature Center Panel

**Files:**
- Modify: `platforms/macos/Atlas/FeatureTogglePanel.swift`

- [ ] **Step 1: Replace the feature toggle panel UI**

Replace `platforms/macos/Atlas/FeatureTogglePanel.swift` with:

```swift
import SwiftUI

struct FeatureCenterPanel: View {
    let features: [AtlasFeature]
    @Binding var enabledFeatures: [String: Bool]
    let onFeatureChanged: (String, Bool) -> Void

    var body: some View {
        Group {
            HStack {
                Text("Feature Center")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(enabledCount)/\(features.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(features) { feature in
                    Toggle(isOn: Binding(
                        get: { enabledFeatures[feature.name, default: feature.isEnabled] },
                        set: { enabled in
                            enabledFeatures[feature.name] = enabled
                            onFeatureChanged(feature.name, enabled)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                            Text(feature.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var enabledCount: Int {
        features.filter { feature in
            enabledFeatures[feature.name, default: feature.isEnabled]
        }.count
    }
}
```

- [ ] **Step 2: Parse Swift files to verify expected failure**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: FAIL because `ContentView` still references `FeatureTogglePanel`.

- [ ] **Step 3: Commit is intentionally deferred**

Do not commit this task by itself if parse fails. Continue directly to Task 5 in the same working tree, then commit Task 4 and Task 5 together after `ContentView` is updated.

---

### Task 5: ContentView Feature Lifecycle

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Modify: `platforms/macos/Atlas/FeatureTogglePanel.swift`

- [ ] **Step 1: Update ContentView feature state properties**

In `platforms/macos/Atlas/ContentView.swift`, replace:

```swift
@State private var features: [String] = []
@State private var enabledFeatures: [String: Bool] = [:]
```

with:

```swift
@State private var features: [AtlasFeature] = []
@State private var enabledFeatures: [String: Bool] = [:]
```

- [ ] **Step 2: Replace FeatureTogglePanel usage**

In `body`, replace:

```swift
FeatureTogglePanel(
    features: features,
    enabledFeatures: $enabledFeatures,
    onFeatureChanged: handleFeatureChange
)
```

with:

```swift
FeatureCenterPanel(
    features: features,
    enabledFeatures: $enabledFeatures,
    onFeatureChanged: handleFeatureChange
)
```

- [ ] **Step 3: Replace startModules**

Replace the existing `startModules()` method with:

```swift
private func startModules() {
    do {
        let loadedFeatures = try AtlasBridge.listFeatures()
        features = loadedFeatures
        enabledFeatures = Dictionary(
            uniqueKeysWithValues: loadedFeatures.map { ($0.name, $0.isEnabled) }
        )
        statusText = "Atlas is Ready"

        if isFeatureEnabled(.monitoring) {
            startMonitoring()
        }
    } catch {
        statusText = "Atlas feature loading failed"
        showStatus(error.localizedDescription, kind: .error, autoHide: false)
    }
}
```

- [ ] **Step 4: Replace handleFeatureChange**

Replace the existing `handleFeatureChange(_:enabled:)` method with:

```swift
private func handleFeatureChange(_ feature: String, enabled: Bool) {
    do {
        let didToggle = try AtlasBridge.toggleFeature(name: feature, enabled: enabled)
        guard didToggle else {
            enabledFeatures[feature] = false
            showStatus("Unknown feature: \(feature)", kind: .error, autoHide: false)
            return
        }

        refreshFeature(feature, enabled: enabled)
    } catch {
        enabledFeatures[feature] = !enabled
        showStatus(error.localizedDescription, kind: .error, autoHide: false)
    }
}
```

- [ ] **Step 5: Add refreshFeature helper**

Add this helper below `handleFeatureChange(_:enabled:)`:

```swift
private func refreshFeature(_ feature: String, enabled: Bool) {
    features = features.map { current in
        current.name == feature
            ? AtlasFeature(name: current.name, isEnabled: enabled)
            : current
    }

    guard feature == AtlasModule.monitoring.featureName else { return }

    if enabled {
        startMonitoring()
    } else {
        do {
            try AtlasBridge.stopMonitoring()
            snapshot = nil
        } catch {
            showStatus(error.localizedDescription, kind: .error, autoHide: false)
        }
    }
}
```

- [ ] **Step 6: Keep isFeatureEnabled unchanged**

Confirm `isFeatureEnabled(_:)` still reads from `enabledFeatures`:

```swift
private func isFeatureEnabled(_ module: AtlasModule) -> Bool {
    enabledFeatures[module.featureName, default: false]
}
```

- [ ] **Step 7: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS.

- [ ] **Step 8: Run feature-related tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' \
  -only-testing:AtlasTests/FeatureModelsTests \
  -only-testing:AtlasTests/FeatureServiceTests \
  -only-testing:AtlasTests/AtlasBridgeFeatureTests
```

Expected: PASS, 9 tests.

- [ ] **Step 9: Build app**

Run:

```bash
xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 10: Commit Task 4 and Task 5 together**

```bash
git add platforms/macos/Atlas/FeatureTogglePanel.swift \
  platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): add feature center panel"
```

---

### Task 6: Rust Feature Ordering and FFI Regression Tests

**Files:**
- Modify: `crates/atlas-core/src/features.rs`
- Modify: `crates/atlas-ffi/src/lib.rs`

- [ ] **Step 1: Add deterministic feature ordering test**

In `crates/atlas-core/src/features.rs`, add this test inside the existing `#[cfg(test)] mod tests` block:

```rust
#[test]
fn test_list_features_is_sorted_by_name() {
    let fm = FeatureManager::new();
    let names: Vec<String> = fm
        .list_features()
        .into_iter()
        .map(|(name, _)| name)
        .collect();

    assert_eq!(
        names,
        vec![
            "monitoring".to_string(),
            "screenshot".to_string(),
            "window-manager".to_string(),
        ]
    );
}
```

- [ ] **Step 2: Run the new Rust test to verify it fails**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
```

Expected: FAIL because `HashMap` iteration order is not guaranteed.

- [ ] **Step 3: Make `list_features` deterministic**

In `crates/atlas-core/src/features.rs`, replace:

```rust
pub fn list_features(&self) -> Vec<(String, FeatureStatus)> {
    self.features.iter().map(|(k, v)| (k.clone(), *v)).collect()
}
```

with:

```rust
pub fn list_features(&self) -> Vec<(String, FeatureStatus)> {
    let mut features: Vec<(String, FeatureStatus)> = self
        .features
        .iter()
        .map(|(name, status)| (name.clone(), *status))
        .collect();
    features.sort_by(|left, right| left.0.cmp(&right.0));
    features
}
```

- [ ] **Step 4: Strengthen FFI feature management test**

In `crates/atlas-ffi/src/lib.rs`, replace the existing `test_feature_management` test with:

```rust
#[test]
fn test_feature_management() {
    let features = list_features().unwrap();
    let names: Vec<String> = features.iter().map(|f| f.name.clone()).collect();

    assert_eq!(
        names,
        vec![
            "monitoring".to_string(),
            "screenshot".to_string(),
            "window-manager".to_string(),
        ]
    );
    assert!(features.iter().any(|f| f.name == "monitoring"));
    assert!(features.iter().any(|f| f.name == "screenshot"));
    assert!(features.iter().any(|f| f.name == "window-manager"));

    assert!(toggle_feature("monitoring".to_string(), true).unwrap());

    let features = list_features().unwrap();
    let monitoring = features
        .iter()
        .find(|feature| feature.name == "monitoring")
        .expect("monitoring feature should exist");
    assert!(matches!(monitoring.status, FeatureStatus::Enabled));

    assert!(!toggle_feature("non-existent".to_string(), true).unwrap());
}
```

- [ ] **Step 5: Run Rust feature tests**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
cargo test -p atlas-ffi test_feature_management
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add crates/atlas-core/src/features.rs crates/atlas-ffi/src/lib.rs
git commit -m "test: stabilize feature manager ordering"
```

---

### Task 7: Final Verification Notes

**Files:**
- Modify: `docs/superpowers/plans/2026-05-11-feature-center-v1.md`

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

Append this section to `docs/superpowers/plans/2026-05-11-feature-center-v1.md`:

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
  - Manual feature center verification was not performed. On 2026-05-11, user acceptance criteria for these task plans is automated/unit tests passing.
- Remaining limitations:
  - Feature state remains in-memory in the Rust `AtlasCore` singleton and is not persisted across app launches.
  - `window-manager` may appear as a toggle before it has a visible SwiftUI module; toggling it only changes feature state.
  - This plan keeps Feature Center inside the menu bar panel rather than opening a detached Settings window.
```

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-05-11-feature-center-v1.md
git commit -m "docs: record feature center verification"
```

---

## Self-Review

1. **Spec coverage:** The plan replaces Swift feature mocks with real UniFFI list/toggle calls, adds a testable service boundary, splits feature toggles into a dedicated `FeatureCenterPanel`, initializes UI from real feature state, and preserves `port-master` under `monitoring` by not adding a separate toggle.
2. **Placeholder scan:** The plan contains exact paths, concrete code, commands, expected results, and commit messages. It does not use TBD/TODO placeholders or refer to undefined later types before defining them.
3. **Type consistency:** `AtlasFeature`, `AtlasFeatureMapper`, `FeatureProviding`, `FeatureService`, `AtlasBridge.featureService`, `AtlasBridge.listFeatures()`, `AtlasBridge.toggleFeature(name:enabled:)`, and `FeatureCenterPanel` are defined before later tasks reference them. Generated UniFFI names match the current generated Swift surface: `FeatureEntry`, `FeatureStatus.enabled`, `FeatureStatus.disabled`, `Atlas.listFeatures()`, and `Atlas.toggleFeature(name:enabled:)`.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-11-feature-center-v1.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

## Execution Verification Notes

- Rust:
  - `cargo test -p atlas-core -p atlas-ffi`
  - Result: PASS
- Swift parse:
  - `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - Result: PASS
- Xcode build:
  - `xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build`
  - Result: PASS
- Xcode tests:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: PASS
- Manual:
  - Manual feature center verification was not performed. On 2026-05-11, user acceptance criteria is automated/unit tests passing.
- Remaining limitations:
  - Feature state remains in-memory only.
  - `window-manager` toggle may appear before it has a visible module.
  - Feature Center remains inside the menu bar panel.

## Final Review Fix Verification Notes

- Generated UniFFI:
  - `./scripts/generate_uniffi_swift.sh`
  - Result: PASS; `platforms/macos/Generated/AtlasFFI/libatlas_ffi.a` changed.
- Swift parse:
  - `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - Result: PASS
- Targeted Xcode tests:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/FeatureStateTests`
  - Result: PASS, 3 tests.
- Rust:
  - `cargo test -p atlas-core -p atlas-ffi`
  - Result: PASS, 19 atlas-core tests and 4 atlas-ffi tests.
- Full Xcode tests:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: PASS, 50 tests.
- Manual:
  - Manual feature center verification was not performed. User acceptance for this final review fix is automated/unit tests only.
