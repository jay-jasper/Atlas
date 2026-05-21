# Command Palette Developer Tools v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small Developer Tools provider to the Atlas command palette so common developer destinations are searchable and executable without expanding the command palette core.

**Architecture:** Add one `CommandProviding` implementation that owns a fixed list of developer commands. Register the provider in `CommandPaletteState` between Atlas commands and clipboard/app results. Keep v1 deterministic and testable with injectable command actions; do not add shell execution or dynamic project scanning.

**Scope:**
- Add `DeveloperToolsProvider`.
- Register it in `CommandPaletteState`.
- Add unit tests for empty-query behavior, keyword/content matching, category/icon metadata, and command execution.

**Out of scope:**
- Running arbitrary shell commands.
- Project/repository discovery.
- Terminal integration.
- User-configurable developer commands.
- UI changes beyond provider registration.

## Task 1: Developer Tools Provider

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/DeveloperToolsProvider.swift`
- Create: `platforms/macos/AtlasTests/DeveloperToolsProviderTests.swift`
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add provider tests**

Create deterministic XCTest coverage for:
- Empty query returns no results.
- Query `dev` returns developer tool commands.
- Query `activity` matches Activity Monitor command.
- Query `console` matches Console command.
- Query `terminal` matches Terminal command.
- All results use category `Developer` and SF Symbol `hammer`.
- Executing a result calls its injected action.
- Results are capped to a small fixed count.

- [ ] **Step 2: Implement `DeveloperToolsProvider`**

Implement a fixed command list with injectable actions:
- Open Terminal
- Open Activity Monitor
- Open Console
- Open Network Utility equivalent via Network settings is intentionally excluded because modern macOS removed Network Utility.

Default actions should use `NSWorkspace.shared.openApplication(at:configuration:)` or `NSWorkspace.shared.open(_:)` against known application URLs. Test actions should be injectable without opening apps.

`results(for:)` should trim whitespace, return `[]` for blank query, match title and keywords case-insensitively, return at most 5 results, and map commands to `PaletteCommand` with category `Developer`.

- [ ] **Step 3: Register provider**

In `CommandPaletteState`, instantiate `DeveloperToolsProvider()` and register it after `AtlasCommandProvider` and before `ClipboardHistoryProvider`.

- [ ] **Step 4: Add files to Xcode project**

Add `DeveloperToolsProvider.swift` to the `Atlas` target and `DeveloperToolsProviderTests.swift` to the `AtlasTests` target.

- [ ] **Step 5: Verify**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/DeveloperToolsProviderTests \
  -only-testing:AtlasTests/ClipboardHistoryProviderTests \
  -only-testing:AtlasTests/AppLauncherProviderTests
```

Then run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS'
```

- [ ] **Step 6: Commit**

Commit with:

```bash
git commit -m "feat(macos): add command palette developer tools"
```
