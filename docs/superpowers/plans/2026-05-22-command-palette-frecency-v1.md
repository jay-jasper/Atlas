# Command Palette Frecency v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rank command palette results by local usage frequency and recency while preserving the existing provider priority order.

**Architecture:** Add a command usage store that records executions by a stable command key derived from `category` and `title`. Add a pure ranker that sorts each provider's result list by execution count and last execution time, keeping provider groups in their existing order. Wire the store into `CommandPaletteView` so every executed or pushed command records usage before running.

**Tech Stack:** Swift, Foundation `UserDefaults`, existing SwiftUI command palette, XCTest, Xcode project updates via `xcodeproj`.

---

## Scope

This plan implements local frecency ranking for command palette results:

- Record command usage count and last executed timestamp.
- Rank commands inside each provider result set by usage count, then recency.
- Preserve existing provider order:
  - Atlas
  - Developer Tools
  - Window Management
  - Clipboard History
  - Snippets
  - App Launcher
- Record usage for both `.execute` and `.push` actions.
- Keep ranking deterministic and covered by unit tests.

Out of scope:

- Cross-provider global reordering.
- Cloud sync.
- Manual reset UI.
- Per-command pinning/favorites.
- Telemetry or analytics upload.
- Changing provider search algorithms.

## File Map

**New files:**

- `platforms/macos/Atlas/CommandPalette/CommandUsageStore.swift`
  - Defines `CommandUsageRecord`, `CommandUsageRecording`, and `CommandUsageStore`.
  - Persists usage records in `UserDefaults`.
  - Exposes a stable command key helper.

- `platforms/macos/Atlas/CommandPalette/CommandPaletteRanker.swift`
  - Defines a pure ranker that sorts one provider result array using usage records.
  - Keeps unrecorded commands in their original order.

- `platforms/macos/AtlasTests/CommandUsageStoreTests.swift`
  - Tests usage recording, count increments, recency updates, persistence, and clear.

- `platforms/macos/AtlasTests/CommandPaletteRankerTests.swift`
  - Tests frequency ranking, recency tie-breaking, and stable order for unrecorded commands.

**Modified files:**

- `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`
  - Accepts a `CommandUsageRecording`.
  - Ranks each provider's results using `CommandPaletteRanker`.
  - Records usage before executing or pushing a command.

- `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`
  - Owns a `CommandUsageRecording` and injects it into `CommandPaletteView`.

- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new source and test files to the correct targets.

---

## Task 1: Command Usage Store

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/CommandUsageStore.swift`
- Create: `platforms/macos/AtlasTests/CommandUsageStoreTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing usage store tests**

Create `platforms/macos/AtlasTests/CommandUsageStoreTests.swift`:

```swift
import XCTest
@testable import Atlas

final class CommandUsageStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "CommandUsageStoreTests"
    private var now = Date(timeIntervalSince1970: 100)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        now = Date(timeIntervalSince1970: 100)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testCommandKeyUsesCategoryAndTitle() {
        let command = command(title: "Capture Area", category: "Atlas")

        XCTAssertEqual(CommandUsageStore.commandKey(for: command), "Atlas|Capture Area")
    }

    func testRecordUsageCreatesRecord() {
        let store = makeStore()
        let command = command(title: "Copy Email Greeting", category: "Snippet")

        store.recordUsage(for: command)

        XCTAssertEqual(store.usageRecords(), [
            "Snippet|Copy Email Greeting": CommandUsageRecord(
                commandKey: "Snippet|Copy Email Greeting",
                executionCount: 1,
                lastExecutedAt: now
            ),
        ])
    }

    func testRecordUsageIncrementsCountAndUpdatesRecency() {
        let store = makeStore()
        let command = command(title: "Open Terminal", category: "Developer")

        store.recordUsage(for: command)
        now = Date(timeIntervalSince1970: 200)
        store.recordUsage(for: command)

        XCTAssertEqual(store.usageRecords()["Developer|Open Terminal"], CommandUsageRecord(
            commandKey: "Developer|Open Terminal",
            executionCount: 2,
            lastExecutedAt: Date(timeIntervalSince1970: 200)
        ))
    }

    func testRecordsPersistAcrossStoreInstances() {
        let firstStore = makeStore()
        firstStore.recordUsage(for: command(title: "Maximize Frontmost Window", category: "Window"))

        let secondStore = makeStore()

        XCTAssertEqual(secondStore.usageRecords()["Window|Maximize Frontmost Window"]?.executionCount, 1)
    }

    func testClearRemovesRecords() {
        let store = makeStore()
        store.recordUsage(for: command(title: "Bug Report", category: "Snippet"))

        store.clear()

        XCTAssertTrue(store.usageRecords().isEmpty)
    }

    private func makeStore() -> CommandUsageStore {
        CommandUsageStore(defaults: defaults, dateProvider: { self.now })
    }

    private func command(title: String, category: String) -> PaletteCommand {
        PaletteCommand(
            id: UUID(),
            title: title,
            subtitle: nil,
            icon: .sfSymbol("bolt"),
            keywords: [],
            action: .execute({}),
            category: category
        )
    }
}
```

- [ ] **Step 2: Add the test file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
unless group.files.any? { |f| f.path == 'CommandUsageStoreTests.swift' }
  ref = group.new_file('CommandUsageStoreTests.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 3: Run usage store tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/CommandUsageStoreTests
```

Expected: compile failure mentioning missing `CommandUsageStore` and `CommandUsageRecord`.

- [ ] **Step 4: Write the usage store implementation**

Create `platforms/macos/Atlas/CommandPalette/CommandUsageStore.swift`:

```swift
import Foundation

struct CommandUsageRecord: Codable, Equatable, Sendable {
    let commandKey: String
    var executionCount: Int
    var lastExecutedAt: Date
}

protocol CommandUsageRecording {
    func recordUsage(for command: PaletteCommand)
    func usageRecords() -> [String: CommandUsageRecord]
}

final class CommandUsageStore: CommandUsageRecording {
    private static let storageKey = "commandPalette.usageRecords"

    private let defaults: UserDefaults
    private let dateProvider: () -> Date
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        defaults: UserDefaults = .standard,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.dateProvider = dateProvider
    }

    func recordUsage(for command: PaletteCommand) {
        let key = Self.commandKey(for: command)
        var records = usageRecords()
        if var record = records[key] {
            record.executionCount += 1
            record.lastExecutedAt = dateProvider()
            records[key] = record
        } else {
            records[key] = CommandUsageRecord(
                commandKey: key,
                executionCount: 1,
                lastExecutedAt: dateProvider()
            )
        }
        save(records)
    }

    func usageRecords() -> [String: CommandUsageRecord] {
        guard
            let data = defaults.data(forKey: Self.storageKey),
            let records = try? decoder.decode([String: CommandUsageRecord].self, from: data)
        else {
            return [:]
        }
        return records
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    static func commandKey(for command: PaletteCommand) -> String {
        "\(command.category)|\(command.title)"
    }

    private func save(_ records: [String: CommandUsageRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
```

- [ ] **Step 5: Add the source file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']['CommandPalette']
unless group.files.any? { |f| f.path == 'CommandUsageStore.swift' }
  ref = group.new_file('CommandUsageStore.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 6: Run usage store tests to verify they pass**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/CommandUsageStoreTests
```

Expected: `CommandUsageStoreTests` passes with 5 tests and 0 failures.

- [ ] **Step 7: Commit**

Run:

```bash
git add platforms/macos/Atlas/CommandPalette/CommandUsageStore.swift \
        platforms/macos/AtlasTests/CommandUsageStoreTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add command palette usage store"
```

---

## Task 2: Command Palette Ranker

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/CommandPaletteRanker.swift`
- Create: `platforms/macos/AtlasTests/CommandPaletteRankerTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing ranker tests**

Create `platforms/macos/AtlasTests/CommandPaletteRankerTests.swift`:

```swift
import XCTest
@testable import Atlas

final class CommandPaletteRankerTests: XCTestCase {
    func testHigherExecutionCountRanksFirst() {
        let commands = [
            command(title: "Copy Email Greeting", category: "Snippet"),
            command(title: "Copy Bug Report", category: "Snippet"),
        ]
        let records = [
            "Snippet|Copy Email Greeting": record("Snippet|Copy Email Greeting", count: 1, time: 100),
            "Snippet|Copy Bug Report": record("Snippet|Copy Bug Report", count: 3, time: 50),
        ]

        let ranked = CommandPaletteRanker.ranked(commands, records: records)

        XCTAssertEqual(ranked.map(\.title), ["Copy Bug Report", "Copy Email Greeting"])
    }

    func testMoreRecentRecordBreaksEqualCountTie() {
        let commands = [
            command(title: "Open Console", category: "Developer"),
            command(title: "Open Terminal", category: "Developer"),
        ]
        let records = [
            "Developer|Open Console": record("Developer|Open Console", count: 2, time: 100),
            "Developer|Open Terminal": record("Developer|Open Terminal", count: 2, time: 200),
        ]

        let ranked = CommandPaletteRanker.ranked(commands, records: records)

        XCTAssertEqual(ranked.map(\.title), ["Open Terminal", "Open Console"])
    }

    func testRecordedCommandRanksBeforeUnrecordedCommand() {
        let commands = [
            command(title: "Capture Area", category: "Atlas"),
            command(title: "Capture Window", category: "Atlas"),
        ]
        let records = [
            "Atlas|Capture Window": record("Atlas|Capture Window", count: 1, time: 100),
        ]

        let ranked = CommandPaletteRanker.ranked(commands, records: records)

        XCTAssertEqual(ranked.map(\.title), ["Capture Window", "Capture Area"])
    }

    func testUnrecordedCommandsKeepOriginalOrder() {
        let commands = [
            command(title: "Capture Desktop", category: "Atlas"),
            command(title: "Capture Area", category: "Atlas"),
            command(title: "Capture Window", category: "Atlas"),
        ]

        let ranked = CommandPaletteRanker.ranked(commands, records: [:])

        XCTAssertEqual(ranked.map(\.title), ["Capture Desktop", "Capture Area", "Capture Window"])
    }

    func testCommandsWithEqualUsageKeepOriginalOrder() {
        let commands = [
            command(title: "Left", category: "Window"),
            command(title: "Right", category: "Window"),
        ]
        let records = [
            "Window|Left": record("Window|Left", count: 2, time: 100),
            "Window|Right": record("Window|Right", count: 2, time: 100),
        ]

        let ranked = CommandPaletteRanker.ranked(commands, records: records)

        XCTAssertEqual(ranked.map(\.title), ["Left", "Right"])
    }

    private func record(_ key: String, count: Int, time: TimeInterval) -> CommandUsageRecord {
        CommandUsageRecord(
            commandKey: key,
            executionCount: count,
            lastExecutedAt: Date(timeIntervalSince1970: time)
        )
    }

    private func command(title: String, category: String) -> PaletteCommand {
        PaletteCommand(
            id: UUID(),
            title: title,
            subtitle: nil,
            icon: .sfSymbol("bolt"),
            keywords: [],
            action: .execute({}),
            category: category
        )
    }
}
```

- [ ] **Step 2: Add the test file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
unless group.files.any? { |f| f.path == 'CommandPaletteRankerTests.swift' }
  ref = group.new_file('CommandPaletteRankerTests.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 3: Run ranker tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/CommandPaletteRankerTests
```

Expected: compile failure mentioning missing `CommandPaletteRanker`.

- [ ] **Step 4: Write the ranker implementation**

Create `platforms/macos/Atlas/CommandPalette/CommandPaletteRanker.swift`:

```swift
import Foundation

enum CommandPaletteRanker {
    static func ranked(
        _ commands: [PaletteCommand],
        records: [String: CommandUsageRecord]
    ) -> [PaletteCommand] {
        commands
            .enumerated()
            .sorted { lhs, rhs in
                let lhsRecord = records[CommandUsageStore.commandKey(for: lhs.element)]
                let rhsRecord = records[CommandUsageStore.commandKey(for: rhs.element)]

                let lhsCount = lhsRecord?.executionCount ?? 0
                let rhsCount = rhsRecord?.executionCount ?? 0
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }

                let lhsDate = lhsRecord?.lastExecutedAt ?? .distantPast
                let rhsDate = rhsRecord?.lastExecutedAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
```

- [ ] **Step 5: Add the source file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']['CommandPalette']
unless group.files.any? { |f| f.path == 'CommandPaletteRanker.swift' }
  ref = group.new_file('CommandPaletteRanker.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 6: Run store and ranker tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/CommandUsageStoreTests \
  -only-testing:AtlasTests/CommandPaletteRankerTests
```

Expected: both test classes pass with 10 tests and 0 failures.

- [ ] **Step 7: Commit**

Run:

```bash
git add platforms/macos/Atlas/CommandPalette/CommandPaletteRanker.swift \
        platforms/macos/AtlasTests/CommandPaletteRankerTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add command palette frecency ranker"
```

---

## Task 3: Integrate Ranking and Recording

**Files:**
- Modify: `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`
- Modify: `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`
- Test: `platforms/macos/AtlasTests/CommandUsageStoreTests.swift`
- Test: `platforms/macos/AtlasTests/CommandPaletteRankerTests.swift`

- [ ] **Step 1: Update `CommandPaletteView` to inject usage recorder**

In `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`, replace the stored property block at the top of `CommandPaletteView` with:

```swift
struct CommandPaletteView: View {
    let providers: [CommandProviding]
    let onDismiss: () -> Void

    // Injected closure builders for sub-views
    let screenshotLibraryViewBuilder: (() -> AnyView)?
    let portLookupViewBuilder: (() -> AnyView)?
    let windowPickerViewBuilder: (() -> AnyView)?

    private let usageRecorder: CommandUsageRecording

    @State private var query: String = ""
    @State private var stack: [PaletteDestination] = []
    @State private var selectedIndex: Int = 0

    init(
        providers: [CommandProviding],
        onDismiss: @escaping () -> Void,
        screenshotLibraryViewBuilder: (() -> AnyView)? = nil,
        portLookupViewBuilder: (() -> AnyView)? = nil,
        windowPickerViewBuilder: (() -> AnyView)? = nil,
        usageRecorder: CommandUsageRecording = CommandUsageStore()
    ) {
        self.providers = providers
        self.onDismiss = onDismiss
        self.screenshotLibraryViewBuilder = screenshotLibraryViewBuilder
        self.portLookupViewBuilder = portLookupViewBuilder
        self.windowPickerViewBuilder = windowPickerViewBuilder
        self.usageRecorder = usageRecorder
    }

    private var results: [PaletteCommand] {
        let records = usageRecorder.usageRecords()
        return providers.flatMap { provider in
            CommandPaletteRanker.ranked(provider.results(for: query), records: records)
        }
    }
```

This keeps provider order stable because each provider is ranked independently before `flatMap` combines the groups.

- [ ] **Step 2: Record command usage before action execution**

In the same file, replace `execute(_:)` with:

```swift
private func execute(_ command: PaletteCommand) {
    usageRecorder.recordUsage(for: command)

    switch command.action {
    case .execute(let fn):
        fn()
        onDismiss()
    case .push(let dest):
        withAnimation(.easeInOut(duration: 0.18)) {
            stack.append(dest)
            query = ""
            selectedIndex = 0
        }
    }
}
```

- [ ] **Step 3: Update `CommandPaletteController` to inject usage store**

In `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`, change:

```swift
private let providers: [CommandProviding]
```

to:

```swift
private let providers: [CommandProviding]
private let usageRecorder: CommandUsageRecording
```

Then change the initializer from:

```swift
init(providers: [CommandProviding]) {
    self.providers = providers
}
```

to:

```swift
init(
    providers: [CommandProviding],
    usageRecorder: CommandUsageRecording = CommandUsageStore()
) {
    self.providers = providers
    self.usageRecorder = usageRecorder
}
```

Finally, in `show()`, update the `CommandPaletteView` construction from:

```swift
let paletteView = CommandPaletteView(
    providers: providers,
    onDismiss: { [weak self] in
        Task { @MainActor [weak self] in
            self?.hide()
        }
    },
    screenshotLibraryViewBuilder: screenshotLibraryViewBuilder,
    portLookupViewBuilder: portLookupViewBuilder,
    windowPickerViewBuilder: windowPickerViewBuilder
)
```

to:

```swift
let paletteView = CommandPaletteView(
    providers: providers,
    onDismiss: { [weak self] in
        Task { @MainActor [weak self] in
            self?.hide()
        }
    },
    screenshotLibraryViewBuilder: screenshotLibraryViewBuilder,
    portLookupViewBuilder: portLookupViewBuilder,
    windowPickerViewBuilder: windowPickerViewBuilder,
    usageRecorder: usageRecorder
)
```

- [ ] **Step 4: Run focused command palette tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/CommandUsageStoreTests \
  -only-testing:AtlasTests/CommandPaletteRankerTests \
  -only-testing:AtlasTests/CommandPaletteModelsTests \
  -only-testing:AtlasTests/AtlasCommandProviderTests \
  -only-testing:AtlasTests/AppLauncherProviderTests \
  -only-testing:AtlasTests/DeveloperToolsProviderTests \
  -only-testing:AtlasTests/WindowManagementProviderTests \
  -only-testing:AtlasTests/ClipboardHistoryProviderTests \
  -only-testing:AtlasTests/SnippetsProviderTests
```

Expected: selected tests pass with 70 tests and 0 failures.

- [ ] **Step 5: Run full macOS test suite**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS'
```

Expected: full suite passes. Existing CoreSimulator/linkd warnings are non-blocking if the test run ends with `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

Run:

```bash
git add platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift \
        platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift
git commit -m "feat(macos): apply command palette frecency ranking"
```

---

## Task 4: Record Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-22-command-palette-frecency-v1.md`

- [ ] **Step 1: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-22-command-palette-frecency-v1.md`:

```markdown
## Verification Notes

Completed on 2026-05-22 on branch `codex/command-palette-frecency-v1`.

- Focused command palette tests:
  - `CommandUsageStoreTests`
  - `CommandPaletteRankerTests`
  - `CommandPaletteModelsTests`
  - `AtlasCommandProviderTests`
  - `AppLauncherProviderTests`
  - `DeveloperToolsProviderTests`
  - `WindowManagementProviderTests`
  - `ClipboardHistoryProviderTests`
  - `SnippetsProviderTests`
- Full macOS test suite:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Manual command palette ranking verification was not run; this follows the project preference that unit tests are sufficient unless explicitly requested.
```

- [ ] **Step 2: Commit plan verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-command-palette-frecency-v1.md
git commit -m "docs: add command palette frecency plan"
```

---

## Self-Review

1. **Spec coverage:** This plan records command usage, persists it locally, ranks each provider's results by frequency and recency, preserves provider order, records `.execute` and `.push` usage, and verifies behavior with deterministic unit tests.

2. **Placeholder scan:** The plan contains concrete file paths, exact test code, exact implementation code, commands, expected results, and commit messages. It avoids undefined placeholder work.

3. **Type consistency:** `CommandUsageRecord`, `CommandUsageRecording`, `CommandUsageStore`, and `CommandPaletteRanker` are defined before later tasks reference them. `CommandPaletteView` and `CommandPaletteController` use the same `CommandUsageRecording` protocol introduced in Task 1.
