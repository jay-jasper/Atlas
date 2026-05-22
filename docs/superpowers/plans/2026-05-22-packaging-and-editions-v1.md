# Packaging and Editions v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local packaging and commercial feature boundaries for Atlas editions without adding payment processing, subscriptions, network license checks, App Store receipt validation, or server-side entitlement calls.

**Architecture:** Keep v1 entirely local in the macOS Swift layer. Edition metadata is static app metadata, entitlement state is injected through a small provider protocol, and feature availability is evaluated locally by combining the selected edition with feature metadata. The Feature Center remains the runtime enable/disable surface; edition availability only labels and blocks unavailable commercial features before they are toggled on.

**Tech Stack:** Swift, SwiftUI, Foundation, UserDefaults, XCTest, existing Rust Feature Center registry, existing Swift `AtlasModule`/`AtlasFeature` models, explicit Xcode PBX project membership.

---

## Scope

This plan implements:

- Free, Pro, and Community edition metadata.
- Local entitlement evaluation through an injected `EntitlementProviding` boundary.
- Feature availability labels in the Feature Center.
- No-network fallback behavior that keeps Atlas usable when entitlement state is missing or unknown.
- Tests with injected entitlement state and isolated `UserDefaults` suites.
- Explicit Xcode project membership updates for all new Swift app and test files.

Out of scope:

- Payment processing.
- Subscription creation, renewal, cancellation, or billing UI.
- Network license checks.
- App Store receipt validation.
- Server-issued tokens, signature validation, or cloud sync.
- Rust or UniFFI APIs beyond preserving existing feature registration behavior.

## Current Baseline

The required audit command:

```bash
rg -n 'Base Pack|Pro Pack|subscription|license|entitlement|edition|paywall|trial' platforms/macos/Atlas platforms/macos/AtlasTests docs
```

currently shows edition language only in `docs/superpowers/specs/2026-05-09-atlas-design.md` and this roadmap. There is no production `Edition`, `Entitlement`, `Paywall`, `License`, or subscription model under `platforms/macos/Atlas`, and no entitlement tests under `platforms/macos/AtlasTests`.

## File Map

**New files:**

- `platforms/macos/Atlas/EditionModels.swift`
  - Defines local edition metadata, feature packaging, local entitlement state, and availability labels.
- `platforms/macos/Atlas/EntitlementService.swift`
  - Evaluates local feature availability from injected entitlement state and static feature packaging.
- `platforms/macos/Atlas/EditionPanel.swift`
  - Shows the current local edition and packaged feature availability without purchase or subscription actions.
- `platforms/macos/AtlasTests/EntitlementServiceTests.swift`
  - Verifies free/pro/community availability, no-network fallback, and injected entitlement state.
- `platforms/macos/AtlasTests/EditionModelsTests.swift`
  - Verifies edition metadata and user-facing labels.

**Modified files:**

- `platforms/macos/Atlas/AtlasModule.swift`
  - Adds module cases for child-plan features additively as needed by the final local packaging matrix. Preserve adjacent child-plan cases if they already exist.
- `platforms/macos/Atlas/FeatureModels.swift`
  - Extends `AtlasFeature` with optional availability metadata and labels.
- `platforms/macos/Atlas/FeatureTogglePanel.swift`
  - Displays availability labels and disables toggles for unavailable features.
- `platforms/macos/Atlas/ContentView.swift`
  - Owns an `EntitlementService`, evaluates feature availability after feature loading, refreshes labels when local entitlement state changes, and shows `EditionPanel`.
- `platforms/macos/AtlasTests/FeatureModelsTests.swift`
  - Adds availability label coverage without replacing existing mapping tests.
- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds every new Swift app file to the `Atlas` target sources and every new Swift test file to the `AtlasTests` target sources.

Project membership rule: this repo uses explicit PBX project references. Every new Swift app file must be added as a `PBXFileReference`, a `PBXBuildFile`, a group entry, and a `PBXSourcesBuildPhase` entry in `platforms/macos/Atlas.xcodeproj/project.pbxproj`. Every new Swift test file must be added the same way for the `AtlasTests` target before running `xcodebuild test`.

---

## Task 1: Add Edition Models

**Files:**
- Create: `platforms/macos/Atlas/EditionModels.swift`
- Create: `platforms/macos/AtlasTests/EditionModelsTests.swift`

- [ ] **Step 1: Create edition and packaging models**

Create `platforms/macos/Atlas/EditionModels.swift`:

```swift
import Foundation

enum AtlasEdition: String, CaseIterable, Identifiable, Codable, Equatable {
    case free
    case pro
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free:
            return "Free"
        case .pro:
            return "Pro"
        case .community:
            return "Community"
        }
    }

    var subtitle: String {
        switch self {
        case .free:
            return "Core local utilities"
        case .pro:
            return "Advanced local productivity modules"
        case .community:
            return "Community build with local-only access"
        }
    }
}

struct EditionFeaturePackage: Equatable {
    let featureName: String
    let includedEditions: Set<AtlasEdition>
    let label: String

    func isIncluded(in edition: AtlasEdition) -> Bool {
        includedEditions.contains(edition)
    }
}

enum EntitlementSource: Equatable {
    case bundled
    case localOverride
    case unavailable
}

struct LocalEntitlementState: Equatable {
    let edition: AtlasEdition
    let source: EntitlementSource
    let note: String

    static let fallback = LocalEntitlementState(
        edition: .free,
        source: .unavailable,
        note: "Using Free edition because no local entitlement is configured."
    )
}

enum FeatureAvailability: Equatable {
    case available(label: String)
    case unavailable(requiredEdition: AtlasEdition, label: String)

    var isAvailable: Bool {
        switch self {
        case .available:
            return true
        case .unavailable:
            return false
        }
    }

    var displayLabel: String {
        switch self {
        case .available(let label):
            return label
        case .unavailable(_, let label):
            return label
        }
    }
}

enum EditionCatalog {
    static let packages: [EditionFeaturePackage] = [
        EditionFeaturePackage(
            featureName: AtlasModule.monitoring.featureName,
            includedEditions: [.free, .pro, .community],
            label: "Included"
        ),
        EditionFeaturePackage(
            featureName: AtlasModule.screenshot.featureName,
            includedEditions: [.free, .pro, .community],
            label: "Included"
        ),
        EditionFeaturePackage(
            featureName: "window-manager",
            includedEditions: [.free, .pro, .community],
            label: "Included"
        ),
        EditionFeaturePackage(
            featureName: "tokenbar",
            includedEditions: [.pro, .community],
            label: "Pro"
        ),
        EditionFeaturePackage(
            featureName: "workspaces",
            includedEditions: [.pro, .community],
            label: "Pro"
        ),
        EditionFeaturePackage(
            featureName: "ai-skills",
            includedEditions: [.pro, .community],
            label: "Pro"
        )
    ]

    static func package(for featureName: String) -> EditionFeaturePackage {
        packages.first { $0.featureName == featureName } ?? EditionFeaturePackage(
            featureName: featureName,
            includedEditions: [.free, .pro, .community],
            label: "Included"
        )
    }
}
```

If adjacent child plans have already added `AtlasModule.tokenbar`, `AtlasModule.workspaces`, or `AtlasModule.aiSkills`, use those cases in the catalog instead of string literals:

```swift
EditionFeaturePackage(
    featureName: AtlasModule.tokenbar.featureName,
    includedEditions: [.pro, .community],
    label: "Pro"
)
```

Preserve any existing child-plan cases and builders. Do not replace `AtlasModule` or `EditionCatalog.packages` with a closed list that drops features added by other workers.

- [ ] **Step 2: Add edition model tests**

Create `platforms/macos/AtlasTests/EditionModelsTests.swift`:

```swift
import XCTest
@testable import Atlas

final class EditionModelsTests: XCTestCase {
    func testEditionMetadataIsStable() {
        XCTAssertEqual(AtlasEdition.free.title, "Free")
        XCTAssertEqual(AtlasEdition.pro.title, "Pro")
        XCTAssertEqual(AtlasEdition.community.title, "Community")
        XCTAssertEqual(AtlasEdition.free.subtitle, "Core local utilities")
        XCTAssertEqual(AtlasEdition.pro.subtitle, "Advanced local productivity modules")
        XCTAssertEqual(AtlasEdition.community.subtitle, "Community build with local-only access")
    }

    func testKnownCoreFeaturesAreIncludedForFreeEdition() {
        XCTAssertTrue(EditionCatalog.package(for: "monitoring").isIncluded(in: .free))
        XCTAssertTrue(EditionCatalog.package(for: "screenshot").isIncluded(in: .free))
        XCTAssertTrue(EditionCatalog.package(for: "window-manager").isIncluded(in: .free))
    }

    func testKnownProFeaturesAreNotIncludedForFreeEdition() {
        XCTAssertFalse(EditionCatalog.package(for: "tokenbar").isIncluded(in: .free))
        XCTAssertFalse(EditionCatalog.package(for: "workspaces").isIncluded(in: .free))
        XCTAssertFalse(EditionCatalog.package(for: "ai-skills").isIncluded(in: .free))
    }

    func testUnknownFeatureDefaultsToIncludedToAvoidAccidentalPaywalling() {
        let package = EditionCatalog.package(for: "future-local-tool")

        XCTAssertEqual(package.label, "Included")
        XCTAssertTrue(package.isIncluded(in: .free))
        XCTAssertTrue(package.isIncluded(in: .pro))
        XCTAssertTrue(package.isIncluded(in: .community))
    }
}
```

- [ ] **Step 3: Add Xcode project membership**

Add these files to `platforms/macos/Atlas.xcodeproj/project.pbxproj`:

- `EditionModels.swift` in the `Atlas` group and `Atlas` sources build phase.
- `EditionModelsTests.swift` in the `AtlasTests` group and `AtlasTests` sources build phase.

Use the existing PBX style in the file: one `PBXFileReference`, one `PBXBuildFile`, one group entry, and one `PBXSourcesBuildPhase` entry per Swift source.

- [ ] **Step 4: Verify model behavior**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/EditionModelsTests
```

Expected: edition metadata tests pass and unknown features default to included.

---

## Task 2: Add Local Entitlement Evaluation

**Files:**
- Create: `platforms/macos/Atlas/EntitlementService.swift`
- Create: `platforms/macos/AtlasTests/EntitlementServiceTests.swift`

- [ ] **Step 1: Create entitlement provider and evaluator**

Create `platforms/macos/Atlas/EntitlementService.swift`:

```swift
import Foundation

protocol EntitlementProviding {
    func currentEntitlement() -> LocalEntitlementState
}

struct LocalEntitlementProvider: EntitlementProviding {
    private enum Keys {
        static let edition = "atlas.localEdition"
    }

    private let defaults: UserDefaults
    private let bundledEdition: AtlasEdition

    init(defaults: UserDefaults = .standard, bundledEdition: AtlasEdition = .free) {
        self.defaults = defaults
        self.bundledEdition = bundledEdition
    }

    func currentEntitlement() -> LocalEntitlementState {
        if let rawEdition = defaults.string(forKey: Keys.edition),
           let edition = AtlasEdition(rawValue: rawEdition) {
            return LocalEntitlementState(
                edition: edition,
                source: .localOverride,
                note: "Using local edition override."
            )
        }

        return LocalEntitlementState(
            edition: bundledEdition,
            source: .bundled,
            note: "Using bundled local edition."
        )
    }

    func saveLocalOverride(_ edition: AtlasEdition) {
        defaults.set(edition.rawValue, forKey: Keys.edition)
    }

    func clearLocalOverride() {
        defaults.removeObject(forKey: Keys.edition)
    }
}

final class EntitlementService {
    private let provider: EntitlementProviding
    private let packageForFeature: (String) -> EditionFeaturePackage

    init(
        provider: EntitlementProviding,
        packageForFeature: @escaping (String) -> EditionFeaturePackage = EditionCatalog.package(for:)
    ) {
        self.provider = provider
        self.packageForFeature = packageForFeature
    }

    func currentState() -> LocalEntitlementState {
        provider.currentEntitlement()
    }

    func availability(for featureName: String) -> FeatureAvailability {
        let state = provider.currentEntitlement()
        let package = packageForFeature(featureName)

        if package.isIncluded(in: state.edition) {
            return .available(label: package.label)
        }

        let requiredEdition = package.includedEditions.contains(.pro) ? AtlasEdition.pro : AtlasEdition.community
        return .unavailable(
            requiredEdition: requiredEdition,
            label: "\(requiredEdition.title) required"
        )
    }

    func availabilityByFeatureName(for features: [AtlasFeature]) -> [String: FeatureAvailability] {
        Dictionary(uniqueKeysWithValues: features.map { feature in
            (feature.name, availability(for: feature.name))
        })
    }
}

struct StaticEntitlementProvider: EntitlementProviding {
    let state: LocalEntitlementState

    func currentEntitlement() -> LocalEntitlementState {
        state
    }
}

struct FallbackEntitlementProvider: EntitlementProviding {
    func currentEntitlement() -> LocalEntitlementState {
        .fallback
    }
}
```

`FallbackEntitlementProvider` is the no-network fallback. It must never attempt network I/O and must keep core local features available through the Free edition. In v1, do not add `URLSession`, receipt readers, purchase SDKs, subscription SDKs, or remote license verification.

- [ ] **Step 2: Add entitlement service tests**

Create `platforms/macos/AtlasTests/EntitlementServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class EntitlementServiceTests: XCTestCase {
    func testFreeEditionAllowsCoreFeaturesAndBlocksProFeatures() {
        let service = EntitlementService(provider: StaticEntitlementProvider(state: LocalEntitlementState(
            edition: .free,
            source: .bundled,
            note: "test"
        )))

        XCTAssertTrue(service.availability(for: "monitoring").isAvailable)
        XCTAssertTrue(service.availability(for: "screenshot").isAvailable)
        XCTAssertFalse(service.availability(for: "tokenbar").isAvailable)
        XCTAssertEqual(service.availability(for: "tokenbar").displayLabel, "Pro required")
    }

    func testProEditionAllowsProFeatures() {
        let service = EntitlementService(provider: StaticEntitlementProvider(state: LocalEntitlementState(
            edition: .pro,
            source: .localOverride,
            note: "test"
        )))

        XCTAssertTrue(service.availability(for: "tokenbar").isAvailable)
        XCTAssertTrue(service.availability(for: "workspaces").isAvailable)
        XCTAssertTrue(service.availability(for: "ai-skills").isAvailable)
    }

    func testCommunityEditionAllowsCommunityAndProPackagedFeaturesLocally() {
        let service = EntitlementService(provider: StaticEntitlementProvider(state: LocalEntitlementState(
            edition: .community,
            source: .bundled,
            note: "test"
        )))

        XCTAssertTrue(service.availability(for: "monitoring").isAvailable)
        XCTAssertTrue(service.availability(for: "tokenbar").isAvailable)
        XCTAssertTrue(service.availability(for: "workspaces").isAvailable)
    }

    func testNoNetworkFallbackUsesFreeEdition() {
        let service = EntitlementService(provider: FallbackEntitlementProvider())

        XCTAssertEqual(service.currentState(), .fallback)
        XCTAssertTrue(service.availability(for: "monitoring").isAvailable)
        XCTAssertFalse(service.availability(for: "tokenbar").isAvailable)
    }

    func testAvailabilityMapUsesInjectedEntitlementState() {
        let features = [
            AtlasFeature(name: "monitoring", isEnabled: false),
            AtlasFeature(name: "tokenbar", isEnabled: false)
        ]
        let service = EntitlementService(provider: StaticEntitlementProvider(state: LocalEntitlementState(
            edition: .free,
            source: .bundled,
            note: "test"
        )))

        let availability = service.availabilityByFeatureName(for: features)

        XCTAssertEqual(availability["monitoring"], .available(label: "Included"))
        XCTAssertEqual(availability["tokenbar"], .unavailable(requiredEdition: .pro, label: "Pro required"))
    }

    func testLocalProviderPersistsOnlyEditionMetadata() {
        let defaults = UserDefaults(suiteName: "EntitlementServiceTests.localProvider")!
        defaults.removePersistentDomain(forName: "EntitlementServiceTests.localProvider")
        let provider = LocalEntitlementProvider(defaults: defaults, bundledEdition: .free)

        provider.saveLocalOverride(.pro)

        XCTAssertEqual(provider.currentEntitlement(), LocalEntitlementState(
            edition: .pro,
            source: .localOverride,
            note: "Using local edition override."
        ))
        XCTAssertEqual(defaults.string(forKey: "atlas.localEdition"), "pro")

        provider.clearLocalOverride()
        XCTAssertEqual(provider.currentEntitlement(), LocalEntitlementState(
            edition: .free,
            source: .bundled,
            note: "Using bundled local edition."
        ))
    }
}
```

- [ ] **Step 3: Add Xcode project membership**

Add these files to `platforms/macos/Atlas.xcodeproj/project.pbxproj`:

- `EntitlementService.swift` in the `Atlas` group and `Atlas` sources build phase.
- `EntitlementServiceTests.swift` in the `AtlasTests` group and `AtlasTests` sources build phase.

- [ ] **Step 4: Verify local entitlement evaluation**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/EntitlementServiceTests
```

Expected: entitlement tests pass using only injected providers and isolated `UserDefaults`; no network calls occur.

---

## Task 3: Add Feature Availability Labels

**Files:**
- Modify: `platforms/macos/Atlas/FeatureModels.swift`
- Modify: `platforms/macos/Atlas/FeatureTogglePanel.swift`
- Modify: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

- [ ] **Step 1: Extend feature model additively**

Update `platforms/macos/Atlas/FeatureModels.swift` without replacing existing title mapping behavior:

```swift
struct AtlasFeature: Identifiable, Equatable {
    let name: String
    let isEnabled: Bool
    let availability: FeatureAvailability?

    init(name: String, isEnabled: Bool, availability: FeatureAvailability? = nil) {
        self.name = name
        self.isEnabled = isEnabled
        self.availability = availability
    }

    var id: String { name }

    var title: String {
        AtlasFeatureTitles.title(for: name)
    }

    var isAvailable: Bool {
        availability?.isAvailable ?? true
    }

    var availabilityLabel: String {
        availability?.displayLabel ?? "Included"
    }
}
```

Keep `AtlasFeatureMapper.map(_:)` source-compatible by relying on the default `availability: nil` initializer argument:

```swift
enum AtlasFeatureMapper {
    static func map(_ entry: FeatureEntry) -> AtlasFeature {
        AtlasFeature(
            name: entry.name,
            isEnabled: entry.status == .enabled
        )
    }
}
```

- [ ] **Step 2: Update Feature Center labels and toggle blocking**

Update `platforms/macos/Atlas/FeatureTogglePanel.swift`:

```swift
ForEach(features) { feature in
    Toggle(isOn: Binding(
        get: { enabledFeatures[feature.name, default: feature.isEnabled] },
        set: { enabled in
            guard feature.isAvailable else {
                enabledFeatures[feature.name] = false
                onFeatureChanged(feature.name, false)
                return
            }

            enabledFeatures[feature.name] = enabled
            onFeatureChanged(feature.name, enabled)
        }
    )) {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(feature.title)
                Spacer()
                Text(feature.availabilityLabel)
                    .font(.caption)
                    .foregroundColor(feature.isAvailable ? .secondary : .orange)
            }
            Text(feature.name).font(.caption).foregroundColor(.secondary)
        }
    }
    .disabled(!feature.isAvailable)
}
```

If other workers have added extra rows or controls to `FeatureCenterPanel`, preserve them and add only the availability label/disabled behavior.

- [ ] **Step 3: Add feature model tests**

Append to `platforms/macos/AtlasTests/FeatureModelsTests.swift`:

```swift
func testDefaultsToAvailableWhenNoEntitlementMetadataIsAttached() {
    let feature = AtlasFeature(name: "monitoring", isEnabled: false)

    XCTAssertTrue(feature.isAvailable)
    XCTAssertEqual(feature.availabilityLabel, "Included")
}

func testUsesAttachedAvailabilityMetadata() {
    let feature = AtlasFeature(
        name: "tokenbar",
        isEnabled: false,
        availability: .unavailable(requiredEdition: .pro, label: "Pro required")
    )

    XCTAssertFalse(feature.isAvailable)
    XCTAssertEqual(feature.availabilityLabel, "Pro required")
}
```

- [ ] **Step 4: Verify feature label model behavior**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureModelsTests
```

Expected: existing title tests and new availability metadata tests pass.

---

## Task 4: Wire Local Availability Into ContentView

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Test: `platforms/macos/AtlasTests/EntitlementServiceTests.swift`

- [ ] **Step 1: Add injectable entitlement service**

In `platforms/macos/Atlas/ContentView.swift`, add an entitlement service property near existing service properties:

```swift
private let entitlementService: EntitlementService
```

Add an initializer that preserves existing call sites:

```swift
init(
    paletteState: CommandPaletteState? = nil,
    entitlementService: EntitlementService = EntitlementService(provider: LocalEntitlementProvider())
) {
    self.paletteState = paletteState
    self.entitlementService = entitlementService
}
```

If `ContentView` already has an initializer from another child plan, extend that initializer additively by adding the `entitlementService` parameter with the same default. Do not remove adjacent injected services.

- [ ] **Step 2: Attach availability after loading features**

In `startModules()`, replace the direct assignment:

```swift
features = loadedFeatures
enabledFeatures = FeatureStateReducer.enabledMap(from: loadedFeatures)
```

with:

```swift
features = loadedFeatures.map { feature in
    AtlasFeature(
        name: feature.name,
        isEnabled: feature.isEnabled,
        availability: entitlementService.availability(for: feature.name)
    )
}
enabledFeatures = FeatureStateReducer.enabledMap(from: features)
```

- [ ] **Step 3: Block unavailable toggles before reaching the bridge**

In `handleFeatureChange`, add the local availability guard before calling `AtlasBridge.toggleFeature`:

```swift
if entitlementService.availability(for: feature).isAvailable == false {
    enabledFeatures[feature] = false
    showStatus("Feature requires a different Atlas edition", kind: .error)
    return
}
```

Keep the existing monitoring start/stop behavior after successful bridge toggles.

- [ ] **Step 4: Add no-network fallback note in UI state**

After successful feature loading in `startModules()`, read the current entitlement state:

```swift
let entitlementState = entitlementService.currentState()
statusText = entitlementState.source == .unavailable ? "Atlas is Ready - Free edition fallback" : "Atlas is Ready"
```

This is a local status string only. Do not add network retry, license refresh, purchase restore, or subscription status checks.

- [ ] **Step 5: Verify content integration through entitlement tests and build**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/EntitlementServiceTests -only-testing:AtlasTests/FeatureModelsTests
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: entitlement/model tests pass and the app target builds.

---

## Task 5: Add Edition Panel

**Files:**
- Create: `platforms/macos/Atlas/EditionPanel.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Create local edition panel**

Create `platforms/macos/Atlas/EditionPanel.swift`:

```swift
import SwiftUI

struct EditionPanel: View {
    let state: LocalEntitlementState
    let packages: [EditionFeaturePackage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Edition").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Text(state.edition.title).font(.caption).foregroundColor(.secondary)
            }

            Text(state.edition.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(state.note)
                .font(.caption)
                .foregroundColor(state.source == .unavailable ? .orange : .secondary)

            ForEach(packages, id: \.featureName) { package in
                HStack {
                    Text(package.featureName)
                    Spacer()
                    Text(package.isIncluded(in: state.edition) ? package.label : "\(requiredEdition(for: package).title) required")
                        .font(.caption)
                        .foregroundColor(package.isIncluded(in: state.edition) ? .secondary : .orange)
                }
                .font(.caption)
            }
        }
    }

    private func requiredEdition(for package: EditionFeaturePackage) -> AtlasEdition {
        package.includedEditions.contains(.pro) ? .pro : .community
    }
}
```

Do not add purchase buttons, price displays, subscription copy, restore purchase controls, external links, or network refresh controls in v1.

- [ ] **Step 2: Show the panel in ContentView**

In `platforms/macos/Atlas/ContentView.swift`, add the panel near `FeatureCenterPanel`:

```swift
EditionPanel(
    state: entitlementService.currentState(),
    packages: EditionCatalog.packages
)

Divider()
```

Keep existing panels in their current order unless another child plan has already reorganized the screen. The edition panel should be visible as local metadata, not as a paywall modal.

- [ ] **Step 3: Add Xcode project membership**

Add `EditionPanel.swift` to the `Atlas` group and the `Atlas` sources build phase in `platforms/macos/Atlas.xcodeproj/project.pbxproj`.

- [ ] **Step 4: Verify app build**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: the app builds with the local edition panel. There are no new payment, subscription, receipt, or network dependencies.

---

## Task 6: Preserve Shared Feature Registration Additively

**Files:**
- Modify only if needed: `crates/atlas-core/src/features.rs`
- Modify only if needed: `platforms/macos/Atlas/AtlasModule.swift`
- Modify only if needed: `platforms/macos/Atlas/FeatureModels.swift`
- Test: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

- [ ] **Step 1: Audit adjacent child-plan feature cases**

Run:

```bash
rg -n 'case .*token|case .*workspace|case .*privacy|case .*clipboard|case .*scratchpad|case .*system|case .*ai|features.insert|AtlasFeatureTitles' crates/atlas-core/src/features.rs platforms/macos/Atlas/AtlasModule.swift platforms/macos/Atlas/FeatureModels.swift docs/superpowers/plans
```

Expected: shows which adjacent roadmap child plans have already added feature names.

- [ ] **Step 2: Preserve adjacent cases and builders**

When adding edition-related references:

- Do not replace `AtlasModule` with a new closed enum body.
- Do not remove feature names already inserted into `FeatureManager::new()`.
- Do not replace `AtlasFeatureTitles.title(for:)` with a mapping that drops adjacent child-plan names.
- Prefer `assert!(names.contains(...))` in feature tests instead of exact arrays when multiple roadmap tasks may have landed.

If a needed module case is missing, add only the missing case and title branch. Example additive snippet:

```swift
case tokenbar

case .tokenbar:
    return "TokenBar"
```

If the case is already present, do not duplicate it.

- [ ] **Step 3: Verify shared registration surfaces**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureModelsTests
```

Expected: shared feature registration remains sorted and feature title tests still pass.

---

## Task 7: Final Verification and Commit

**Files:**
- All files changed by this child execution.

- [ ] **Step 1: Run required focused tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/EditionModelsTests -only-testing:AtlasTests/EntitlementServiceTests -only-testing:AtlasTests/FeatureModelsTests
```

Expected: all edition, entitlement, and feature model tests pass.

- [ ] **Step 2: Run app build**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: the app builds. The implementation contains no real payment processing, subscription SDKs, network license checks, App Store receipt validation, or server entitlement calls.

- [ ] **Step 3: Audit forbidden v1 surfaces**

Run:

```bash
rg -n 'StoreKit|SKPayment|subscription|receipt|URLSession|license server|paywall|restore purchase|trial' platforms/macos/Atlas platforms/macos/AtlasTests
```

Expected: no matches for payment, subscription, receipt, paywall, network license, or restore-purchase production code introduced by this task. Existing documentation-only matches are acceptable outside `platforms/macos/Atlas` and `platforms/macos/AtlasTests`.

- [ ] **Step 4: Review project membership**

Run:

```bash
rg -n 'EditionModels|EntitlementService|EditionPanel|EditionModelsTests|EntitlementServiceTests' platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: each new Swift app/test file appears in PBX file references, build files, group entries, and sources build phases.

- [ ] **Step 5: Commit implementation**

Run:

```bash
git status --short
git add platforms/macos/Atlas/EditionModels.swift platforms/macos/Atlas/EntitlementService.swift platforms/macos/Atlas/EditionPanel.swift platforms/macos/Atlas/FeatureModels.swift platforms/macos/Atlas/FeatureTogglePanel.swift platforms/macos/Atlas/ContentView.swift platforms/macos/AtlasTests/EditionModelsTests.swift platforms/macos/AtlasTests/EntitlementServiceTests.swift platforms/macos/AtlasTests/FeatureModelsTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "Add local Atlas editions"
```

Expected: the implementation commit contains only the local edition metadata/evaluation work and explicit PBX membership updates.

## Safety Notes

- Unknown features default to included so the metadata layer does not accidentally block child-plan features that have not yet been assigned commercial packaging.
- Community edition is local-only in v1 and uses the same local entitlement evaluator as Free and Pro.
- Pro labels are informational availability labels, not purchase prompts.
- No-network fallback is represented by `FallbackEntitlementProvider` and `LocalEntitlementState.fallback`; it does not perform retries or remote checks.
- Tests inject `StaticEntitlementProvider` or isolated `UserDefaults` state. They do not depend on user account state, network availability, StoreKit, or App Store receipts.
