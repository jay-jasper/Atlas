# Translation Settings v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app Translation Settings panel so users can configure the existing Atlas-compatible HTTP translation endpoint, API key, and model used by screenshot translation.

**Architecture:** Reuse the existing `ScreenshotTranslationConfigurationStore` and `ScreenshotTranslationServiceFactory.live()` path introduced by Translation Engine v1. Add write/clear helpers to the store, a small SwiftUI settings view that edits a draft model, and wire the panel into `ContentView` without changing the screenshot editor translation flow. Configuration is still local `UserDefaults` for v1; Keychain-backed secret storage and provider presets remain future work.

**Tech Stack:** SwiftUI, Foundation `UserDefaults`, XCTest, existing `ScreenshotTranslating` provider architecture.

---

## Scope Check

This plan covers Translation Settings v1 only:

- Add a focused settings draft model for endpoint/API key/model form state.
- Add `UserDefaults` save/clear helpers for translation configuration.
- Add a compact `TranslationSettingsPanel` inside the existing menu-bar content.
- Keep the current translation engine contract unchanged.
- Keep translation disabled-by-default behavior when no valid endpoint is configured.

This plan does not implement Keychain, provider presets, settings import/export, endpoint connectivity tests, language selection, separate Preferences window, or real provider-specific adapters.

## File Structure

- Modify: `platforms/macos/Atlas/ScreenshotTranslationConfiguration.swift`
  - Add `ScreenshotTranslationSettingsDraft`.
  - Add `settingsDraft()`, `save(_:)`, and `clear()` on `ScreenshotTranslationConfigurationStore`.
- Create: `platforms/macos/Atlas/TranslationSettingsPanel.swift`
  - SwiftUI panel with endpoint/API key/model fields.
  - Save and Clear buttons.
  - Derived status text showing configured/unconfigured/invalid endpoint state.
- Modify: `platforms/macos/Atlas/ContentView.swift`
  - Add translation settings state.
  - Load settings on appear.
  - Show `TranslationSettingsPanel` near Feature Center.
  - Save/clear settings through `ScreenshotTranslationConfigurationStore`.
  - Reset `AtlasBridge.translationService` to `ScreenshotTranslationServiceFactory.live()` after saves/clears so the current process uses fresh config.
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Add `TranslationSettingsPanel.swift` to the Atlas target.
- Modify: `platforms/macos/AtlasTests/ScreenshotTranslationConfigurationTests.swift`
  - Add store save/clear/draft tests.
- Create: `platforms/macos/AtlasTests/TranslationSettingsPanelTests.swift`
  - Test draft status text and invalid endpoint state without UI snapshots.
- Modify: `docs/superpowers/plans/2026-05-20-translation-settings-v1.md`
  - Record final verification notes after implementation.

---

### Task 1: Configuration Draft and Store Writes

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotTranslationConfiguration.swift`
- Modify: `platforms/macos/AtlasTests/ScreenshotTranslationConfigurationTests.swift`

- [ ] **Step 1: Add failing store write tests**

Append these tests to `platforms/macos/AtlasTests/ScreenshotTranslationConfigurationTests.swift`:

```swift
func testSettingsDraftReadsStoredValues() {
    defaults.set(" https://example.com/translate ", forKey: ScreenshotTranslationConfigurationKeys.endpoint)
    defaults.set(" secret ", forKey: ScreenshotTranslationConfigurationKeys.apiKey)
    defaults.set(" atlas-test ", forKey: ScreenshotTranslationConfigurationKeys.model)

    let store = ScreenshotTranslationConfigurationStore(defaults: defaults)
    let draft = store.settingsDraft()

    XCTAssertEqual(draft.endpoint, " https://example.com/translate ")
    XCTAssertEqual(draft.apiKey, " secret ")
    XCTAssertEqual(draft.model, " atlas-test ")
}

func testSaveTrimsValuesAndUpdatesHTTPConfig() {
    let store = ScreenshotTranslationConfigurationStore(defaults: defaults)

    store.save(
        ScreenshotTranslationSettingsDraft(
            endpoint: " https://example.com/translate ",
            apiKey: " secret ",
            model: " atlas-test "
        )
    )

    let config = store.httpConfig()

    XCTAssertEqual(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.endpoint), "https://example.com/translate")
    XCTAssertEqual(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.apiKey), "secret")
    XCTAssertEqual(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.model), "atlas-test")
    XCTAssertEqual(config?.endpoint.absoluteString, "https://example.com/translate")
    XCTAssertEqual(config?.apiKey, "secret")
    XCTAssertEqual(config?.model, "atlas-test")
}

func testSaveRemovesBlankOptionalValues() {
    defaults.set("old-secret", forKey: ScreenshotTranslationConfigurationKeys.apiKey)
    defaults.set("old-model", forKey: ScreenshotTranslationConfigurationKeys.model)
    let store = ScreenshotTranslationConfigurationStore(defaults: defaults)

    store.save(
        ScreenshotTranslationSettingsDraft(
            endpoint: "https://example.com/translate",
            apiKey: " ",
            model: "\n"
        )
    )

    XCTAssertNil(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.apiKey))
    XCTAssertNil(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.model))
    XCTAssertEqual(store.httpConfig()?.endpoint.absoluteString, "https://example.com/translate")
}

func testClearRemovesAllTranslationSettings() {
    defaults.set("https://example.com/translate", forKey: ScreenshotTranslationConfigurationKeys.endpoint)
    defaults.set("secret", forKey: ScreenshotTranslationConfigurationKeys.apiKey)
    defaults.set("atlas-test", forKey: ScreenshotTranslationConfigurationKeys.model)
    let store = ScreenshotTranslationConfigurationStore(defaults: defaults)

    store.clear()

    XCTAssertNil(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.endpoint))
    XCTAssertNil(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.apiKey))
    XCTAssertNil(defaults.string(forKey: ScreenshotTranslationConfigurationKeys.model))
    XCTAssertNil(store.httpConfig())
}
```

- [ ] **Step 2: Run configuration tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests
```

Expected: FAIL with missing `ScreenshotTranslationSettingsDraft`, `settingsDraft()`, `save(_:)`, and `clear()`.

- [ ] **Step 3: Add draft model and store write helpers**

Update `platforms/macos/Atlas/ScreenshotTranslationConfiguration.swift` to include this `ScreenshotTranslationSettingsDraft` directly after `ScreenshotTranslationConfigurationKeys`:

```swift
struct ScreenshotTranslationSettingsDraft: Equatable {
    var endpoint: String
    var apiKey: String
    var model: String

    static let empty = ScreenshotTranslationSettingsDraft(endpoint: "", apiKey: "", model: "")

    var trimmedEndpoint: String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedApiKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

Then add these methods inside `ScreenshotTranslationConfigurationStore`, below `init(defaults:)` and above `httpConfig()`:

```swift
func settingsDraft() -> ScreenshotTranslationSettingsDraft {
    ScreenshotTranslationSettingsDraft(
        endpoint: defaults.string(forKey: ScreenshotTranslationConfigurationKeys.endpoint) ?? "",
        apiKey: defaults.string(forKey: ScreenshotTranslationConfigurationKeys.apiKey) ?? "",
        model: defaults.string(forKey: ScreenshotTranslationConfigurationKeys.model) ?? ""
    )
}

func save(_ draft: ScreenshotTranslationSettingsDraft) {
    setStringOrRemove(draft.trimmedEndpoint, forKey: ScreenshotTranslationConfigurationKeys.endpoint)
    setStringOrRemove(draft.trimmedApiKey, forKey: ScreenshotTranslationConfigurationKeys.apiKey)
    setStringOrRemove(draft.trimmedModel, forKey: ScreenshotTranslationConfigurationKeys.model)
}

func clear() {
    defaults.removeObject(forKey: ScreenshotTranslationConfigurationKeys.endpoint)
    defaults.removeObject(forKey: ScreenshotTranslationConfigurationKeys.apiKey)
    defaults.removeObject(forKey: ScreenshotTranslationConfigurationKeys.model)
}
```

Then add this private helper inside `ScreenshotTranslationConfigurationStore`, below `cleanedOptionalString(_:)`:

```swift
private func setStringOrRemove(_ value: String, forKey key: String) {
    if value.isEmpty {
        defaults.removeObject(forKey: key)
        return
    }

    defaults.set(value, forKey: key)
}
```

- [ ] **Step 4: Run configuration tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add platforms/macos/Atlas/ScreenshotTranslationConfiguration.swift \
  platforms/macos/AtlasTests/ScreenshotTranslationConfigurationTests.swift
git commit -m "feat(macos): add translation settings persistence"
```

---

### Task 2: Translation Settings Panel Model and View

**Files:**
- Create: `platforms/macos/Atlas/TranslationSettingsPanel.swift`
- Create: `platforms/macos/AtlasTests/TranslationSettingsPanelTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add failing settings panel tests**

Create `platforms/macos/AtlasTests/TranslationSettingsPanelTests.swift`:

```swift
import XCTest
@testable import Atlas

final class TranslationSettingsPanelTests: XCTestCase {
    func testEmptyDraftStatusIsNotConfigured() {
        let state = TranslationSettingsPanelState(
            draft: .empty,
            isConfigured: false
        )

        XCTAssertEqual(state.statusText, "Translation endpoint not configured")
        XCTAssertFalse(state.canSave)
    }

    func testValidEndpointCanSave() {
        let state = TranslationSettingsPanelState(
            draft: ScreenshotTranslationSettingsDraft(
                endpoint: "https://example.com/translate",
                apiKey: "",
                model: ""
            ),
            isConfigured: true
        )

        XCTAssertEqual(state.statusText, "Translation endpoint configured")
        XCTAssertTrue(state.canSave)
    }

    func testInvalidEndpointStatus() {
        let state = TranslationSettingsPanelState(
            draft: ScreenshotTranslationSettingsDraft(
                endpoint: "not a url",
                apiKey: "",
                model: ""
            ),
            isConfigured: false
        )

        XCTAssertEqual(state.statusText, "Translation endpoint is invalid")
        XCTAssertFalse(state.canSave)
    }
}
```

- [ ] **Step 2: Add test file to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `TranslationSettingsPanelTests.swift` is listed in:

```text
PBXFileReference
PBXBuildFile
AtlasTests group
AtlasTests Sources build phase
```

- [ ] **Step 3: Run panel tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/TranslationSettingsPanelTests
```

Expected: FAIL with missing `TranslationSettingsPanelState`.

- [ ] **Step 4: Add settings panel implementation**

Create `platforms/macos/Atlas/TranslationSettingsPanel.swift`:

```swift
import SwiftUI

struct TranslationSettingsPanelState: Equatable {
    let draft: ScreenshotTranslationSettingsDraft
    let isConfigured: Bool

    var canSave: Bool {
        isValidEndpoint
    }

    var statusText: String {
        if draft.trimmedEndpoint.isEmpty {
            return "Translation endpoint not configured"
        }

        if !isValidEndpoint {
            return "Translation endpoint is invalid"
        }

        return isConfigured ? "Translation endpoint configured" : "Translation endpoint ready to save"
    }

    private var isValidEndpoint: Bool {
        guard let url = URL(string: draft.trimmedEndpoint),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              let host = url.host else {
            return false
        }

        let cleanedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanedHost.isEmpty
            && cleanedHost != "."
            && !cleanedHost.contains("_")
            && !cleanedHost.hasPrefix(".")
            && !cleanedHost.hasSuffix(".")
    }
}

struct TranslationSettingsPanel: View {
    @State private var draft: ScreenshotTranslationSettingsDraft
    let isConfigured: Bool
    let onSave: (ScreenshotTranslationSettingsDraft) -> Void
    let onClear: () -> Void

    init(
        draft: ScreenshotTranslationSettingsDraft,
        isConfigured: Bool,
        onSave: @escaping (ScreenshotTranslationSettingsDraft) -> Void,
        onClear: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.isConfigured = isConfigured
        self.onSave = onSave
        self.onClear = onClear
    }

    var body: some View {
        let state = TranslationSettingsPanelState(draft: draft, isConfigured: isConfigured)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Translation").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Text(state.statusText).font(.caption).foregroundColor(state.canSave || draft.trimmedEndpoint.isEmpty ? .secondary : .red)
            }

            TextField("https://example.com/translate", text: $draft.endpoint)
                .textFieldStyle(.roundedBorder)

            SecureField("API key", text: $draft.apiKey)
                .textFieldStyle(.roundedBorder)

            TextField("Model", text: $draft.model)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save") {
                    onSave(draft)
                }
                .disabled(!state.canSave)

                Button("Clear") {
                    draft = .empty
                    onClear()
                }

                Spacer()
            }
        }
    }
}
```

- [ ] **Step 5: Add app source file to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so `TranslationSettingsPanel.swift` is listed in:

```text
PBXFileReference
PBXBuildFile
Atlas group
Atlas Sources build phase
```

- [ ] **Step 6: Run panel tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/TranslationSettingsPanelTests
```

Expected: PASS, 3 tests.

- [ ] **Step 7: Commit**

```bash
git add platforms/macos/Atlas/TranslationSettingsPanel.swift \
  platforms/macos/AtlasTests/TranslationSettingsPanelTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add translation settings panel"
```

---

### Task 3: Wire Translation Settings Into ContentView

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Add translation settings state and helpers**

In `platforms/macos/Atlas/ContentView.swift`, add these state properties below `isTranslatingScreenshotText`:

```swift
@State private var translationSettingsDraft: ScreenshotTranslationSettingsDraft = .empty
@State private var isTranslationConfigured: Bool = false
private let translationConfigurationStore = ScreenshotTranslationConfigurationStore()
```

Then add these helper methods below `startModules()`:

```swift
private func loadTranslationSettings() {
    translationSettingsDraft = translationConfigurationStore.settingsDraft()
    isTranslationConfigured = translationConfigurationStore.httpConfig() != nil
}

private func saveTranslationSettings(_ draft: ScreenshotTranslationSettingsDraft) {
    translationConfigurationStore.save(draft)
    AtlasBridge.translationService = ScreenshotTranslationServiceFactory.live()
    loadTranslationSettings()
    showStatus(isTranslationConfigured ? "Translation settings saved" : "Translation endpoint is invalid", kind: isTranslationConfigured ? .success : .error)
}

private func clearTranslationSettings() {
    translationConfigurationStore.clear()
    AtlasBridge.translationService = ScreenshotTranslationServiceFactory.live()
    loadTranslationSettings()
    showStatus("Translation settings cleared")
}
```

- [ ] **Step 2: Load settings on appear**

In `startModules()`, insert this line as the first statement:

```swift
loadTranslationSettings()
```

- [ ] **Step 3: Render settings panel**

In `ContentView.body`, after `FeatureCenterPanel(...)` and before the following `Divider()`, insert:

```swift
Divider()

TranslationSettingsPanel(
    draft: translationSettingsDraft,
    isConfigured: isTranslationConfigured,
    onSave: saveTranslationSettings,
    onClear: clearTranslationSettings
)
```

The surrounding block should look like this:

```swift
FeatureCenterPanel(
    features: features,
    enabledFeatures: $enabledFeatures,
    onFeatureChanged: handleFeatureChange
)

Divider()

TranslationSettingsPanel(
    draft: translationSettingsDraft,
    isConfigured: isTranslationConfigured,
    onSave: saveTranslationSettings,
    onClear: clearTranslationSettings
)

Divider()

AppFooter()
```

- [ ] **Step 4: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [ ] **Step 5: Run focused settings tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests -only-testing:AtlasTests/TranslationSettingsPanelTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): wire translation settings panel"
```

---

### Task 4: Final Verification and Plan Notes

**Files:**
- Modify: `docs/superpowers/plans/2026-05-20-translation-settings-v1.md`

- [x] **Step 1: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [x] **Step 2: Run focused translation settings tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests -only-testing:AtlasTests/TranslationSettingsPanelTests -only-testing:AtlasTests/ScreenshotTranslationServiceTests
```

Expected: PASS.

- [x] **Step 3: Run full macOS tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected: PASS. The existing CoreSimulator out-of-date warning is acceptable if macOS tests run and `TEST SUCCEEDED` appears.

- [x] **Step 4: Run Rust core tests**

Run:

```bash
cargo test -p atlas-core
```

Expected: PASS.

- [x] **Step 5: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-20-translation-settings-v1.md`:

```markdown
---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
- Focused translation settings tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests -only-testing:AtlasTests/TranslationSettingsPanelTests -only-testing:AtlasTests/ScreenshotTranslationServiceTests`
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Rust core tests: `cargo test -p atlas-core`

Translation Settings v1 intentionally uses UserDefaults because Translation Engine v1 already reads from UserDefaults. Keychain-backed API key storage, provider presets, and endpoint connectivity checks remain future work.
```

- [x] **Step 6: Commit verification notes**

```bash
git add docs/superpowers/plans/2026-05-20-translation-settings-v1.md
git commit -m "docs: record translation settings v1 verification"
```

---

## Self-Review

1. **Spec coverage:** This plan configures the existing Translation Engine v1 endpoint/API key/model path from the UI, persists values, clears values, updates the live service after changes, and verifies behavior with focused tests. It intentionally excludes Keychain, provider presets, connectivity tests, and a separate preferences window.
2. **Placeholder scan:** No task uses incomplete placeholder instructions. Each implementation step contains concrete code or exact project-file edit intent.
3. **Type consistency:** `ScreenshotTranslationSettingsDraft`, `TranslationSettingsPanelState`, `TranslationSettingsPanel`, `settingsDraft()`, `save(_:)`, and `clear()` are introduced before later tasks use them.

---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift` passed with no output.
- Focused translation settings tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotTranslationConfigurationTests -only-testing:AtlasTests/TranslationSettingsPanelTests -only-testing:AtlasTests/ScreenshotTranslationServiceTests` passed with 23 tests.
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'` passed with 92 tests. Xcode emitted the existing CoreSimulator out-of-date warning, but macOS tests ran and `TEST SUCCEEDED` appeared.
- Rust core tests: `cargo test -p atlas-core` passed with 21 tests.

Translation Settings v1 intentionally uses UserDefaults because Translation Engine v1 already reads from UserDefaults. Keychain-backed API key storage, provider presets, and endpoint connectivity checks remain future work.
