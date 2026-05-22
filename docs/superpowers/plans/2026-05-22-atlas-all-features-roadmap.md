# Atlas All Features Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the full Atlas product surface described in the 2026 design spec as a sequence of independently testable macOS modules.

**Architecture:** Atlas remains a native SwiftUI menu bar app backed by focused Swift services and a Rust core exposed through UniFFI only when cross-language core logic is needed. The work is split by subsystem so each feature can ship behind Feature Center controls, run only when enabled, and be verified without requiring the entire product to be finished.

**Tech Stack:** SwiftUI, AppKit, Accessibility APIs, Vision, CoreGraphics, UserDefaults/file-backed local stores, Rust, UniFFI, sysinfo, cargo test, XCTest.

---

## Scope Check

The request covers every Atlas feature, which spans multiple independent subsystems: feature management, monitoring, screenshot/OCR/translation, clipboard, scratchpad, command automation, window/workspace management, system utilities, privacy monitoring, and AI skills. Do not implement this as one giant code change.

Use this file as the master execution map. For each subsystem below, either execute the existing detailed plan listed here or write a new detailed child plan before touching code. Each child plan must follow the same `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md` format and must end in working, testable software on its own.

## Existing Implementation Baseline

- Screenshot capture, annotation, pinning, library, OCR, translation, drag output, feature settings, and translation settings are partially implemented in `crates/atlas-core/src/capture/engine.rs`, exposed through `crates/atlas-ffi/src/atlas.udl`, and bridged through `platforms/macos/Atlas/AtlasCaptureService.swift`, `Screenshot*.swift`, `FloatingScreenshotThumbnailWindow.swift`, `PinnedScreenshotWindow.swift`, `WindowCaptureService.swift`, and `WindowSelectionWindow.swift`.
- Monitoring and Port Master are partially implemented in `crates/atlas-core/src/monitor/`, `platforms/macos/Atlas/MonitoringService.swift`, `MonitoringPanel.swift`, `MonitoringFFIMapper.swift`, `PortMasterPanel.swift`, and `crates/atlas-ffi/src/atlas.udl`.
- Enhanced monitoring data models for per-core CPU, process lists, network interfaces, disk, battery, and temperature are implemented in `crates/atlas-core/src/monitor/models.rs`, `collector.rs`, `disk.rs`, `battery.rs`, `sensors.rs`, and exposed through `crates/atlas-ffi/src/atlas.udl`.
- Feature toggles are partially implemented in `crates/atlas-core/src/features.rs`, `crates/atlas-ffi/src/atlas.udl`, `platforms/macos/Atlas/FeatureService.swift`, `FeatureModels.swift`, `FeatureState.swift`, and `FeatureTogglePanel.swift`.
- Command Palette is partially implemented in `platforms/macos/Atlas/CommandPalette/`, including app launching, app rescans, Atlas commands, developer tools, snippets, frecency ranking, clipboard history, and window management providers.
- Window management is partially implemented in `platforms/macos/Atlas/WindowManagementService.swift` and `platforms/macos/Atlas/CommandPalette/WindowManagementProvider.swift`.
- Clipboard history is partially implemented as an in-memory command provider in `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift`.
- Scratchpad, advanced system utilities, Privacy Pulse, AI skills, workspaces, scrolling capture, GIF recording, TokenBar, and AI load monitoring remain planned.

## File Structure Map

### Master Planning Files

- Modify: `docs/superpowers/plans/2026-05-22-atlas-all-features-roadmap.md`
  - Owns execution order, dependency gates, and subsystem boundaries.
- Existing child plans under `docs/superpowers/plans/`
  - Reuse existing plans when they still match the current code.
- Create future child plans under `docs/superpowers/plans/`
  - One child plan per subsystem listed in Task 3 through Task 13.

### Cross-Cutting Product Files

- Modify: `crates/atlas-core/src/features.rs`
  - Owns Rust-side feature names and default state.
- Modify: `crates/atlas-ffi/src/atlas.udl`
  - Owns public Rust-to-Swift API declarations.
- Modify: `crates/atlas-ffi/src/lib.rs`
  - Owns UniFFI function implementation.
- Modify: `platforms/macos/Atlas/FeatureModels.swift`
  - Owns local Swift feature metadata.
- Modify: `platforms/macos/Atlas/FeatureService.swift`
  - Owns Swift access to the feature registry.
- Modify: `platforms/macos/Atlas/FeatureTogglePanel.swift`
  - Owns the visible Feature Center UI.
- Modify: `platforms/macos/Atlas/ContentView.swift`
  - Owns composition of enabled panels.
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
  - Owns app-level service construction and command providers.

### Subsystem File Areas

- Screenshot/OCR/translation: `platforms/macos/Atlas/Screenshot*.swift`
- Monitoring and Port Master: `crates/atlas-core/src/monitor/`, `platforms/macos/Atlas/Monitoring*.swift`, `platforms/macos/Atlas/PortMasterPanel.swift`
- Command Palette: `platforms/macos/Atlas/CommandPalette/*.swift`
- Clipboard: `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift`, future `platforms/macos/Atlas/Clipboard*.swift`
- Scratchpad: future `platforms/macos/Atlas/Scratchpad*.swift`
- Window/workspace management: `platforms/macos/Atlas/Window*.swift`, future `platforms/macos/Atlas/Workspace*.swift`
- System utilities: future `platforms/macos/Atlas/SystemUtilities*.swift`
- Privacy Pulse: future `platforms/macos/Atlas/PrivacyPulse*.swift`
- AI skills and automation: future `platforms/macos/Atlas/Automation*.swift`, `platforms/macos/Atlas/Skills*.swift`

## Execution Gates

- Gate A: `cargo test` passes before and after Rust or UniFFI changes.
- Gate B: Narrow XCTest targets pass after each Swift subsystem change.
- Gate C: The app builds in Xcode after every feature that touches project membership.
- Gate D: A feature is not considered shipped until it is visible in Feature Center and disabled modules do not start their background services.
- Gate E: Any feature touching Screen Recording, Accessibility, Camera, Microphone, file access, shell execution, or network APIs includes an explicit permission and privacy behavior test.

---

### Task 1: Confirm Current Product Inventory

**Files:**
- Read: `docs/superpowers/specs/2026-05-09-atlas-design.md`
- Read: `docs/superpowers/plans/*.md`
- Read: `platforms/macos/Atlas/**/*.swift`
- Read: `crates/atlas-core/src/**/*.rs`
- Read: `crates/atlas-ffi/src/atlas.udl`

- [x] **Step 1: List existing plan files**

Run:

```bash
find docs/superpowers/plans -maxdepth 1 -type f -name '*.md' | sort
```

Expected: The command prints the current plan list, including screenshot, monitoring, translation, and command palette plans.

- [x] **Step 2: List current Swift feature surfaces**

Run:

```bash
find platforms/macos/Atlas -maxdepth 2 -type f -name '*.swift' | sort
```

Expected: The command prints Swift app files, including `ContentView.swift`, `AtlasBridge.swift`, `FeatureService.swift`, screenshot files, monitoring files, and `CommandPalette/` files.

- [x] **Step 3: List current Rust feature surfaces**

Run:

```bash
find crates -type f \( -name '*.rs' -o -name '*.udl' \) | sort
```

Expected: The command prints Rust and UniFFI files, including `crates/atlas-core/src/features.rs`, `crates/atlas-core/src/monitor/`, and `crates/atlas-ffi/src/atlas.udl`.

- [x] **Step 4: Record the implementation baseline**

Update this plan's "Existing Implementation Baseline" section if the commands above reveal newly added modules. Keep the update factual: module name, primary files, and whether it is implemented, partial, or planned.

- [x] **Step 5: Commit inventory update if the file changed**

Run:

```bash
git diff -- docs/superpowers/plans/2026-05-22-atlas-all-features-roadmap.md
git add docs/superpowers/plans/2026-05-22-atlas-all-features-roadmap.md
git commit -m "docs: add Atlas full feature roadmap"
```

Expected: The diff only changes this roadmap file. The commit succeeds.

---

### Task 2: Normalize Feature Center Before New Modules

**Files:**
- Use existing plan: `docs/superpowers/plans/2026-05-11-feature-center-v1.md`
- Modify in child execution: `crates/atlas-core/src/features.rs`
- Modify in child execution: `crates/atlas-ffi/src/atlas.udl`
- Modify in child execution: `crates/atlas-ffi/src/lib.rs`
- Modify in child execution: `platforms/macos/Atlas/FeatureModels.swift`
- Modify in child execution: `platforms/macos/Atlas/FeatureService.swift`
- Modify in child execution: `platforms/macos/Atlas/FeatureTogglePanel.swift`
- Test in child execution: `platforms/macos/AtlasTests/FeatureServiceTests.swift`
- Test in child execution: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

- [x] **Step 1: Re-read the existing Feature Center plan**

Run:

```bash
sed -n '1,220p' docs/superpowers/plans/2026-05-11-feature-center-v1.md
```

Expected: The plan describes replacing Swift feature mocks with real UniFFI-backed feature entries.

- [x] **Step 2: Audit current feature names**

Run:

```bash
rg -n '"monitoring"|"screenshot"|"window-manager"|AtlasModule|FeatureCenter|FeatureService' crates platforms/macos/Atlas platforms/macos/AtlasTests
```

Expected: The command shows current feature names and reveals any mismatch between Rust, UniFFI, Swift models, tests, and UI.

- [x] **Step 3: Execute or refresh the Feature Center plan**

If `2026-05-11-feature-center-v1.md` still matches the current code, execute it task-by-task. If it refers to deleted or renamed files, create `docs/superpowers/plans/2026-05-22-feature-center-v2.md` with exact current file paths and tests before editing code.

Execution note, 2026-05-22: `2026-05-11-feature-center-v1.md` still matches the current code. Feature Center v1 is already implemented through UniFFI-backed `FeatureService.live`, `AtlasBridge` delegation, `AtlasFeature` mapping, and `FeatureCenterPanel`; no v2 plan or code change was needed.

- [x] **Step 4: Verify Rust feature behavior**

Run:

```bash
cargo test -p atlas-core test_feature_toggle
cargo test -p atlas-core test_toggle_non_existent_feature
cargo test -p atlas-core test_list_features_is_sorted_by_name
```

Expected: Each listed atlas-core feature test command passes.

- [x] **Step 5: Verify Swift feature behavior**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureServiceTests -only-testing:AtlasTests/FeatureModelsTests -only-testing:AtlasTests/AtlasBridgeFeatureTests
```

Expected: Feature service, model, and AtlasBridge delegation tests pass.

- [x] **Step 6: Commit Feature Center verification**

Run:

```bash
git status --short
git add docs/superpowers/plans/2026-05-22-atlas-all-features-roadmap.md
git commit -m "docs: verify feature center normalization"
```

Expected: The commit contains only the roadmap verification update. No normalization code commit is created when Feature Center v1 is already implemented and the required tests pass.

---

### Task 3: Finish Screenshot, OCR, Translation, and Library

**Files:**
- Use existing plan: `docs/superpowers/plans/2026-05-10-screenshot-pro-capture.md`
- Use existing plan: `docs/superpowers/plans/2026-05-10-uniffi-real-capture.md`
- Use existing plan: `docs/superpowers/plans/2026-05-11-screenshot-capture-modes-v2.md`
- Use existing plan: `docs/superpowers/plans/2026-05-11-screenshot-selection-precision-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-20-translation-engine-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-20-translation-settings-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-21-screenshot-annotation-style-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-21-screenshot-annotation-text-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-21-screenshot-drag-output-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-21-screenshot-feature-controls-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-21-screenshot-library-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-21-screenshot-quick-output-feedback-v1.md`
- Created: `docs/superpowers/plans/2026-05-22-scrolling-capture-v1.md`
- Created: `docs/superpowers/plans/2026-05-22-gif-recording-v1.md`

- [x] **Step 1: Audit shipped screenshot surfaces**

Run:

```bash
rg -n 'captureDesktop|captureWindow|captureRegion|OCR|Translate|ScreenshotLibrary|Scrolling|GIF|record' platforms/macos/Atlas platforms/macos/AtlasTests crates/atlas-core crates/atlas-ffi
```

Expected: The command shows implemented capture, OCR, translation, and library paths. It should not show implemented scrolling capture or GIF recording unless those features have been added since this roadmap was written.

Execution note, 2026-05-22: The audit showed implemented capture, OCR, translation, and screenshot library paths in `platforms/macos/Atlas`, `platforms/macos/AtlasTests`, and `crates/atlas-ffi`. Matches for `record` were unrelated command usage/library recording paths; no implemented scrolling capture or GIF recording surface was present.

- [x] **Step 2: Run current screenshot tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/ScreenshotCaptureModeTests -only-testing:AtlasTests/AtlasCaptureServiceTests -only-testing:AtlasTests/ScreenshotLibraryTests -only-testing:AtlasTests/ScreenshotOCRServiceTests -only-testing:AtlasTests/ScreenshotTranslationServiceTests
```

Expected: Existing screenshot, OCR, library, and translation tests pass.

Execution note, 2026-05-22: The requested `xcodebuild test` command passed with 32 selected tests and 0 failures. Xcode emitted non-blocking CoreSimulator version and multiple macOS destination warnings, then completed with `** TEST SUCCEEDED **`.

- [x] **Step 3: Execute remaining existing screenshot plans**

Execute any existing screenshot plan whose acceptance criteria are not yet represented by tests or code. Use the plan file as the source of truth and commit after each plan.

Execution note, 2026-05-22: Existing screenshot child plan acceptance criteria are represented by current code and tests for pro capture, real UniFFI capture, capture modes, selection precision, translation engine/settings, annotation style/text, drag output, feature controls, screenshot library, and quick output feedback. Some older plan files remain unchecked and describe pre-existing/mock-era steps, but their target surfaces now exist; no old plan was re-executed and no screenshot implementation code was changed.

- [x] **Step 4: Write the scrolling capture child plan**

Create `docs/superpowers/plans/2026-05-22-scrolling-capture-v1.md`. The child plan must cover window scroll capture, stitch behavior, permission behavior, image output, library persistence, Feature Center gating, and XCTest coverage.

- [x] **Step 5: Write the GIF recording child plan**

Create `docs/superpowers/plans/2026-05-22-gif-recording-v1.md`. The child plan must cover region selection, frame capture loop, stop control, GIF encoding, output save/copy, Feature Center gating, and tests that avoid requiring live screen recording permission.

- [x] **Step 6: Commit screenshot roadmap expansion**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-scrolling-capture-v1.md docs/superpowers/plans/2026-05-22-gif-recording-v1.md docs/superpowers/plans/2026-05-22-atlas-all-features-roadmap.md
git commit -m "docs: plan advanced screenshot capture"
```

Expected: The commit contains only the two child plan files and this roadmap update.

---

### Task 4: Finish Monitoring, Port Master, TokenBar, and AI Load

**Files:**
- Use existing plan: `docs/superpowers/plans/2026-05-09-system-monitoring.md`
- Use existing plan: `docs/superpowers/plans/2026-05-09-enhanced-monitoring.md`
- Use existing plan: `docs/superpowers/plans/2026-05-11-monitoring-v2-port-master.md`
- Created: `docs/superpowers/plans/2026-05-22-tokenbar-v1.md`
- Created: `docs/superpowers/plans/2026-05-22-local-ai-load-monitor-v1.md`

- [x] **Step 1: Run current monitoring tests**

Run:

```bash
cargo test -p atlas-core monitor
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/MonitoringServiceTests -only-testing:AtlasTests/MonitoringFFIMapperTests -only-testing:AtlasTests/AtlasBridgeMonitoringTests
```

Expected: Rust monitor tests and Swift monitoring mapper/service tests pass.

Execution note, 2026-05-22: `cargo test -p atlas-core monitor` passed with 12 monitor tests. The requested `xcodebuild test` slice passed with 8 tests across `AtlasBridgeMonitoringTests`, `MonitoringFFIMapperTests`, and `MonitoringServiceTests`; Xcode also reported a CoreSimulator version warning, but the macOS test destination completed successfully.

- [x] **Step 2: Audit TokenBar absence or presence**

Run:

```bash
rg -n 'TokenBar|OpenAI|Claude|usage|cost|billing|Ollama|LM Studio|GPU|NPU' crates platforms/macos/Atlas platforms/macos/AtlasTests docs/superpowers/plans
```

Expected: The command identifies whether TokenBar and local AI load monitoring are absent, planned, or partially implemented.

Execution note, 2026-05-22: The audit found TokenBar and local AI load monitoring only in roadmap/planning text. Production `crates/`, `platforms/macos/Atlas`, and `platforms/macos/AtlasTests` matches were existing monitoring `usage` fields and command palette usage tracking. No TokenBar, Ollama, LM Studio, GPU, or NPU production implementation was present.

- [x] **Step 3: Write the TokenBar child plan**

Create `docs/superpowers/plans/2026-05-22-tokenbar-v1.md`. The child plan must cover provider configuration, local cost ledger, manual usage import, API-key storage behavior, command palette actions, Feature Center gating, and tests with injected network transports.

Execution note, 2026-05-22: Created `docs/superpowers/plans/2026-05-22-tokenbar-v1.md` using the writing-plans format. The plan covers provider configuration, Keychain API-key storage, local JSON ledger, manual CSV usage import, injected network transports, command palette actions, Feature Center gating, Xcode project membership, and exact test commands.

- [x] **Step 4: Write the local AI load child plan**

Create `docs/superpowers/plans/2026-05-22-local-ai-load-monitor-v1.md`. The child plan must cover Ollama detection, LM Studio detection, process-level CPU/memory attribution, best-effort GPU/NPU reporting, UI display, Feature Center gating, and tests that use injected process snapshots.

Execution note, 2026-05-22: Created `docs/superpowers/plans/2026-05-22-local-ai-load-monitor-v1.md` using the writing-plans format. The plan covers Ollama and LM Studio process detection, injected process snapshots, CPU and memory aggregation, best-effort GPU/NPU reporting, UI display, Feature Center gating, Xcode project membership, and exact test commands.

- [x] **Step 5: Commit monitoring expansion plans**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-tokenbar-v1.md docs/superpowers/plans/2026-05-22-local-ai-load-monitor-v1.md docs/superpowers/plans/2026-05-22-atlas-all-features-roadmap.md
git commit -m "docs: plan Atlas AI monitoring features"
```

Expected: The commit contains only TokenBar and local AI load monitor child plans plus this Task 4 roadmap execution note.

---

### Task 5: Finish Command Palette and Automation

**Files:**
- Use existing plan: `docs/superpowers/plans/2026-05-21-command-palette-shell-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-21-command-palette-developer-tools-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-22-command-palette-app-rescan-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-22-command-palette-frecency-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-22-command-palette-snippets-v1.md`
- Use existing plan: `docs/superpowers/plans/2026-05-22-command-palette-window-management-v1.md`
- Create later: `docs/superpowers/plans/2026-05-22-command-palette-custom-automation-v1.md`

- [x] **Step 1: Run current command palette tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/CommandPaletteModelsTests -only-testing:AtlasTests/AtlasCommandProviderTests -only-testing:AtlasTests/CommandPaletteRankerTests -only-testing:AtlasTests/CommandUsageStoreTests -only-testing:AtlasTests/AppLauncherProviderTests -only-testing:AtlasTests/DeveloperToolsProviderTests -only-testing:AtlasTests/SnippetsProviderTests -only-testing:AtlasTests/WindowManagementProviderTests
```

Expected: Command palette tests pass.

- [x] **Step 2: Audit automation support**

Run:

```bash
rg -n 'Shell|Python|script|automation|run command|Process\\(' platforms/macos/Atlas platforms/macos/AtlasTests docs/superpowers/plans
```

Expected: The command shows existing shell command plan coverage and any current process execution implementation.

- [x] **Step 3: Execute existing command palette plans**

Execute any existing command palette plan whose acceptance criteria are not yet represented by tests or code. Commit each child plan separately.

Execution note, 2026-05-22: The required command palette XCTest slice passed with 57 tests and 0 failures. The automation audit command showed existing shell command coverage in `2026-05-21-command-palette-shell-v1.md`, monitoring process-kill paths, and plan text, but no current custom automation `Process(` implementation in `platforms/macos/Atlas` or `platforms/macos/AtlasTests`. Existing command palette plans for shell UI, developer tools, app rescans, frecency, snippets, and window management are represented by current providers/tests, so no production code was changed for this task. Custom user-defined shell/Python automation is still missing and is covered by the new child plan.

- [x] **Step 4: Write custom automation child plan**

Create `docs/superpowers/plans/2026-05-22-command-palette-custom-automation-v1.md`. The child plan must cover user-defined shell/Python commands, command storage, execution timeout, output display, permission warnings, Feature Center gating, command ranking, and tests using injected process runners.

- [x] **Step 5: Commit automation plan**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-command-palette-custom-automation-v1.md
git commit -m "docs: plan custom command automation"
```

Expected: The commit contains only the custom automation child plan and this roadmap Task 5 execution note.

---

### Task 6: Finish Clipboard History

**Files:**
- Created: `docs/superpowers/plans/2026-05-22-clipboard-history-v1.md`
- Modify in child execution: `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift`
- Create in child execution: `platforms/macos/Atlas/ClipboardHistoryStore.swift`
- Create in child execution: `platforms/macos/Atlas/ClipboardHistoryPanel.swift`
- Test in child execution: `platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift`
- Test in child execution: `platforms/macos/AtlasTests/ClipboardHistoryStoreTests.swift`

- [x] **Step 1: Audit current clipboard behavior**

Run:

```bash
sed -n '1,220p' platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift
```

Expected: The file shows in-memory text clipboard capture and command palette results.

- [x] **Step 2: Write clipboard history child plan**

Create `docs/superpowers/plans/2026-05-22-clipboard-history-v1.md`. The child plan must cover persistent text history, image metadata handling, search, delete, clear-all, max retention, Feature Center gating, privacy messaging, and tests with an injected clipboard reader.

Execution note, 2026-05-22: `ClipboardHistoryProvider.swift` currently captures non-empty text clipboard contents through the injected `ClipboardReading` abstraction, stores entries in memory, caps history with `maxHistoryCount`, and exposes matching command palette results that copy selected text back to the pasteboard. Created `2026-05-22-clipboard-history-v1.md` as a child implementation plan covering persistent text history, image metadata without image bytes, search, delete, clear-all, max retention, Feature Center gating, privacy messaging, injected-reader tests, and explicit Xcode project membership updates for new Swift app/test files.

- [x] **Step 3: Commit clipboard plan**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-clipboard-history-v1.md
git commit -m "docs: plan persistent clipboard history"
```

Expected: The commit contains only the clipboard history child plan and this roadmap Task 6 execution note.

---

### Task 7: Add Scratchpad

**Files:**
- Create later: `docs/superpowers/plans/2026-05-22-scratchpad-v1.md`
- Create in child execution: `platforms/macos/Atlas/ScratchpadModels.swift`
- Create in child execution: `platforms/macos/Atlas/ScratchpadStore.swift`
- Create in child execution: `platforms/macos/Atlas/ScratchpadPanel.swift`
- Create in child execution: `platforms/macos/Atlas/ScratchpadSummaryService.swift`
- Test in child execution: `platforms/macos/AtlasTests/ScratchpadStoreTests.swift`
- Test in child execution: `platforms/macos/AtlasTests/ScratchpadSummaryServiceTests.swift`

- [ ] **Step 1: Confirm Scratchpad is not already implemented**

Run:

```bash
rg -n 'Scratchpad|scratchpad|note|markdown' platforms/macos/Atlas platforms/macos/AtlasTests docs/superpowers/plans
```

Expected: The command shows no production Scratchpad implementation unless it has been added after this roadmap.

- [ ] **Step 2: Write Scratchpad child plan**

Create `docs/superpowers/plans/2026-05-22-scratchpad-v1.md`. The child plan must cover Markdown note storage, create/edit/delete, command palette access, optional AI summary via injected summarizer, Feature Center gating, and XCTest coverage.

- [ ] **Step 3: Commit Scratchpad plan**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-scratchpad-v1.md
git commit -m "docs: plan Atlas scratchpad"
```

Expected: The commit contains only the Scratchpad child plan.

---

### Task 8: Finish Window Management and Workspaces

**Files:**
- Use existing plan: `docs/superpowers/plans/2026-05-22-command-palette-window-management-v1.md`
- Create later: `docs/superpowers/plans/2026-05-22-window-grid-v1.md`
- Create later: `docs/superpowers/plans/2026-05-22-workspaces-v1.md`
- Modify in child execution: `platforms/macos/Atlas/WindowManagementService.swift`
- Create in child execution: `platforms/macos/Atlas/WindowGridPanel.swift`
- Create in child execution: `platforms/macos/Atlas/WorkspaceModels.swift`
- Create in child execution: `platforms/macos/Atlas/WorkspaceStore.swift`
- Create in child execution: `platforms/macos/Atlas/WorkspacePanel.swift`

- [x] **Step 1: Run current window management tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/WindowManagementServiceTests -only-testing:AtlasTests/WindowManagementProviderTests
```

Expected: Current window management tests pass.

- [x] **Step 2: Write window grid child plan**

Create `docs/superpowers/plans/2026-05-22-window-grid-v1.md`. The child plan must cover 3x3 grid UI, active window targeting, Accessibility permission handling, multi-display coordinate mapping, Feature Center gating, and tests with injected window manager state.

- [x] **Step 3: Write workspaces child plan**

Create `docs/superpowers/plans/2026-05-22-workspaces-v1.md`. The child plan must cover capture current layout, save named workspace, restore layout, missing app/window behavior, command palette actions, Feature Center gating, and tests with injected window snapshots.

- [x] **Step 4: Commit window plans**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-window-grid-v1.md docs/superpowers/plans/2026-05-22-workspaces-v1.md docs/superpowers/plans/2026-05-22-atlas-all-features-roadmap.md
git commit -m "docs: plan window grid and workspaces"
```

Expected: The commit contains only the window grid child plan, workspaces child plan, and this roadmap update.

Execution note, 2026-05-22: The required `xcodebuild test` command passed with 17 selected window management tests and 0 failures. Created `2026-05-22-window-grid-v1.md` covering 3x3 grid UI, active frontmost window targeting, Accessibility permission handling, multi-display coordinate mapping, Feature Center gating, injected-state tests, and explicit Xcode project membership updates. Created `2026-05-22-workspaces-v1.md` covering current layout capture, named workspace save, restore, missing app/window reporting, command palette actions, Feature Center gating, injected window snapshot tests, and explicit Xcode project membership updates. No window grid or workspace production code was implemented in this task.

---

### Task 9: Add System Utility Modules

**Files:**
- Create later: `docs/superpowers/plans/2026-05-22-system-utilities-v1.md`
- Create in child execution: `platforms/macos/Atlas/SystemUtilitiesModels.swift`
- Create in child execution: `platforms/macos/Atlas/KeepAwakeService.swift`
- Create in child execution: `platforms/macos/Atlas/PresentationModeService.swift`
- Create in child execution: `platforms/macos/Atlas/CameraPreviewPanel.swift`
- Create in child execution: `platforms/macos/Atlas/DisplayControlService.swift`
- Test in child execution: `platforms/macos/AtlasTests/KeepAwakeServiceTests.swift`
- Test in child execution: `platforms/macos/AtlasTests/PresentationModeServiceTests.swift`

- [ ] **Step 1: Audit current utility support**

Run:

```bash
rg -n 'awake|caffeinate|presentation|camera|mirror|display|brightness|DDC|mute notifications' platforms/macos/Atlas platforms/macos/AtlasTests docs/superpowers/plans
```

Expected: The command shows whether keep-awake, presentation mode, hand mirror, or display control already exist.

- [ ] **Step 2: Write system utilities child plan**

Create `docs/superpowers/plans/2026-05-22-system-utilities-v1.md`. The child plan must cover keep-awake, presentation mode, hand mirror, DDC/CI capability detection, Feature Center gating, permission behavior, and tests with injected system command adapters.

- [ ] **Step 3: Commit system utilities plan**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-system-utilities-v1.md
git commit -m "docs: plan Atlas system utilities"
```

Expected: The commit contains only the system utilities child plan.

---

### Task 10: Add Privacy Pulse

**Files:**
- Create later: `docs/superpowers/plans/2026-05-22-privacy-pulse-v1.md`
- Create in child execution: `platforms/macos/Atlas/PrivacyPulseModels.swift`
- Create in child execution: `platforms/macos/Atlas/PrivacyPulseService.swift`
- Create in child execution: `platforms/macos/Atlas/PrivacyPulsePanel.swift`
- Test in child execution: `platforms/macos/AtlasTests/PrivacyPulseServiceTests.swift`

- [ ] **Step 1: Audit privacy event support**

Run:

```bash
rg -n 'privacy|camera|microphone|pasteboard|clipboard|permission|Screen Recording|Accessibility' platforms/macos/Atlas platforms/macos/AtlasTests docs/superpowers/plans
```

Expected: The command shows current permission handling and any privacy event tracking.

- [ ] **Step 2: Write Privacy Pulse child plan**

Create `docs/superpowers/plans/2026-05-22-privacy-pulse-v1.md`. The child plan must cover visible status for camera, microphone, clipboard reads, screen recording, Accessibility use, Atlas-internal access logging, Feature Center gating, and tests with injected event sources.

- [ ] **Step 3: Commit Privacy Pulse plan**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-privacy-pulse-v1.md
git commit -m "docs: plan Privacy Pulse"
```

Expected: The commit contains only the Privacy Pulse child plan.

---

### Task 11: Add AI Skills and Workflow Extensions

**Files:**
- Create later: `docs/superpowers/plans/2026-05-22-ai-skills-v1.md`
- Create in child execution: `platforms/macos/Atlas/SkillModels.swift`
- Create in child execution: `platforms/macos/Atlas/SkillStore.swift`
- Create in child execution: `platforms/macos/Atlas/SkillRunner.swift`
- Create in child execution: `platforms/macos/Atlas/SkillPanel.swift`
- Test in child execution: `platforms/macos/AtlasTests/SkillStoreTests.swift`
- Test in child execution: `platforms/macos/AtlasTests/SkillRunnerTests.swift`

- [ ] **Step 1: Audit current skill and workflow support**

Run:

```bash
rg -n 'Skill|workflow|automation|trigger|script|send email|summary' platforms/macos/Atlas platforms/macos/AtlasTests docs/superpowers/plans
```

Expected: The command shows command automation work and whether a dedicated skill interface exists.

- [ ] **Step 2: Write AI Skills child plan**

Create `docs/superpowers/plans/2026-05-22-ai-skills-v1.md`. The child plan must cover skill metadata, trigger types, screenshot-to-summary example, shell/Python execution reuse, permissions, local storage, command palette integration, Feature Center gating, and tests with injected runners.

- [ ] **Step 3: Commit AI Skills plan**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-ai-skills-v1.md
git commit -m "docs: plan Atlas AI skills"
```

Expected: The commit contains only the AI Skills child plan.

---

### Task 12: Add Packaging and Commercial Feature Boundaries

**Files:**
- Create later: `docs/superpowers/plans/2026-05-22-packaging-and-editions-v1.md`
- Create in child execution: `platforms/macos/Atlas/EditionModels.swift`
- Create in child execution: `platforms/macos/Atlas/EntitlementService.swift`
- Create in child execution: `platforms/macos/Atlas/EditionPanel.swift`
- Test in child execution: `platforms/macos/AtlasTests/EntitlementServiceTests.swift`

- [ ] **Step 1: Audit current edition support**

Run:

```bash
rg -n 'Base Pack|Pro Pack|subscription|license|entitlement|edition|paywall|trial' platforms/macos/Atlas platforms/macos/AtlasTests docs
```

Expected: The command shows whether commercial feature boundaries exist.

- [ ] **Step 2: Write packaging and editions child plan**

Create `docs/superpowers/plans/2026-05-22-packaging-and-editions-v1.md`. The child plan must cover free/pro/community edition metadata, local entitlement evaluation, feature availability labels, no-network fallback behavior, and tests with injected entitlement state.

- [ ] **Step 3: Commit packaging plan**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-packaging-and-editions-v1.md
git commit -m "docs: plan Atlas editions"
```

Expected: The commit contains only the packaging and editions child plan.

---

### Task 13: Final Integration Pass

**Files:**
- Modify in child execution: `platforms/macos/Atlas/ContentView.swift`
- Modify in child execution: `platforms/macos/Atlas/AtlasApp.swift`
- Modify in child execution: `platforms/macos/Atlas/AtlasSettingsView.swift`
- Modify in child execution: `platforms/macos/Atlas/FeatureTogglePanel.swift`
- Test in child execution: relevant `platforms/macos/AtlasTests/*.swift`

- [ ] **Step 1: Verify all feature names are centralized**

Run:

```bash
rg -n '"monitoring"|"screenshot"|"window-manager"|"clipboard"|"scratchpad"|"privacy"|"automation"|"tokenbar"' crates platforms/macos/Atlas platforms/macos/AtlasTests
```

Expected: Feature name string literals are concentrated in feature registry/model files and tests. UI and service files should prefer typed feature identifiers where available.

- [ ] **Step 2: Verify all disabled modules stay idle**

Run:

```bash
rg -n 'Timer|DispatchSource|NSEvent.addGlobalMonitor|NSPasteboard|startMonitoring|start\\(|requestAccessibility|CGWindowList|AVCapture' platforms/macos/Atlas
```

Expected: Background services are started through feature-gated entry points, not unconditionally during app launch.

- [ ] **Step 3: Run full Rust test suite**

Run:

```bash
cargo test
```

Expected: All Rust workspace tests pass.

- [ ] **Step 4: Run full macOS test suite**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: All macOS XCTest tests pass.

- [ ] **Step 5: Build app**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: The app builds successfully.

- [ ] **Step 6: Manual app smoke test**

Open `platforms/macos/Atlas.xcodeproj` in Xcode, run the app, and verify:

- Feature Center loads.
- Enabling screenshot shows screenshot controls.
- Enabling monitoring starts live monitoring.
- Command Palette opens and returns Atlas commands.
- Disabling a module hides or idles its background services.
- Permission-gated features show clear status when permission is missing.

- [ ] **Step 7: Commit final integration**

Run:

```bash
git status --short
git add platforms/macos/Atlas platforms/macos/AtlasTests crates docs/superpowers/plans
git commit -m "feat: integrate Atlas feature suite"
```

Expected: The final integration commit contains only changes needed to connect already implemented child features.

---

## Recommended Execution Order

1. Task 1: Inventory.
2. Task 2: Feature Center normalization.
3. Task 3: Screenshot/OCR/translation/library.
4. Task 5: Command Palette and automation.
5. Task 6: Clipboard history.
6. Task 8: Window grid and workspaces.
7. Task 4: Monitoring, TokenBar, and local AI load.
8. Task 7: Scratchpad.
9. Task 9: System utilities.
10. Task 10: Privacy Pulse.
11. Task 11: AI Skills.
12. Task 12: Packaging and editions.
13. Task 13: Final integration.

This order keeps shared infrastructure early and high-risk system permissions late.

## Self-Review

**1. Spec coverage:** The roadmap covers all six spec categories: Monitoring, Data Flow, Layout, Utility, Advanced Agent, and Feature Manager. Existing screenshot, monitoring, translation, command palette, and window plans are reused where available. Missing larger modules are assigned child plans with exact filenames and required coverage.

**2. Placeholder scan:** This roadmap avoids deferred implementation text inside code tasks by requiring child plans before subsystem code edits. No child subsystem is marked complete by this roadmap alone.

**3. Type consistency:** Current file names and module names match the repository baseline: `FeatureService.swift`, `FeatureTogglePanel.swift`, `ContentView.swift`, `AtlasApp.swift`, `crates/atlas-core/src/features.rs`, and `crates/atlas-ffi/src/atlas.udl`.
