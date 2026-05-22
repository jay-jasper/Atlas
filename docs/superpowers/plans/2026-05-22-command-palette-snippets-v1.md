# Command Palette Snippets v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add searchable text snippets to the Atlas command palette, with selected snippets copied to the clipboard.

**Architecture:** Add a small snippet model/store boundary and a `CommandProviding` implementation. The store owns deterministic snippet data and optional `UserDefaults` persistence; the provider only maps snippets to executable palette commands. Clipboard writes reuse the existing `ClipboardReading` abstraction so tests never touch the real pasteboard.

**Tech Stack:** Swift, Foundation `UserDefaults`, AppKit pasteboard abstraction through `ClipboardReading`, SwiftUI command palette models, XCTest, Xcode project updates via `xcodeproj`.

---

## Scope

This plan implements snippets as command palette commands:

- Search snippets by title, body, and keywords.
- Copy the selected snippet body to the clipboard.
- Use built-in default snippets when no snippets have been persisted.
- Persist custom snippet arrays through a small store API for future settings UI.

Out of scope:

- Snippet editing UI.
- Rich text or image snippets.
- Placeholder expansion.
- Keyboard shortcut assignment per snippet.
- Snippet folders/tags beyond flat keywords.
- Sync/import/export.

## File Map

**New files:**

- `platforms/macos/Atlas/SnippetStore.swift`
  - Defines `Snippet`, `SnippetProviding`, and `SnippetStore`.
  - Provides default snippets and JSON persistence in `UserDefaults`.

- `platforms/macos/Atlas/CommandPalette/SnippetsProvider.swift`
  - Implements `CommandProviding`.
  - Searches snippets and copies the selected snippet body through `ClipboardReading`.

- `platforms/macos/AtlasTests/SnippetStoreTests.swift`
  - Tests default snippets, persistence round-trip, blank snippet filtering, and stable identity.

- `platforms/macos/AtlasTests/SnippetsProviderTests.swift`
  - Tests command palette search behavior, command metadata, result cap, and clipboard execution.

**Modified files:**

- `platforms/macos/Atlas/AtlasApp.swift`
  - Registers `SnippetsProvider` after `ClipboardHistoryProvider` and before `AppLauncherProvider`.

- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds the two new source files to the `Atlas` target and the two test files to the `AtlasTests` target.

---

## Task 1: Snippet Store

**Files:**
- Create: `platforms/macos/Atlas/SnippetStore.swift`
- Create: `platforms/macos/AtlasTests/SnippetStoreTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing store tests**

Create `platforms/macos/AtlasTests/SnippetStoreTests.swift`:

```swift
import XCTest
@testable import Atlas

final class SnippetStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SnippetStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultSnippetsAreReturnedWhenStorageIsEmpty() {
        let store = SnippetStore(defaults: defaults)

        let snippets = store.snippets()

        XCTAssertEqual(snippets.map(\.title), [
            "Email Greeting",
            "Meeting Notes",
            "Bug Report",
            "Thank You",
        ])
    }

    func testSnippetHasStableIdentityFromID() {
        let snippet = Snippet(
            id: "thanks",
            title: "Thank You",
            body: "Thanks!",
            keywords: ["thanks"]
        )

        XCTAssertEqual(snippet.id, "thanks")
    }

    func testSaveAndLoadCustomSnippetsRoundTrips() {
        let store = SnippetStore(defaults: defaults)
        let snippets = [
            Snippet(
                id: "custom",
                title: "Custom Reply",
                body: "I will take a look.",
                keywords: ["reply", "custom"]
            )
        ]

        store.save(snippets)

        XCTAssertEqual(store.snippets(), snippets)
    }

    func testSaveFiltersBlankTitleOrBodySnippets() {
        let store = SnippetStore(defaults: defaults)
        let snippets = [
            Snippet(id: "good", title: "Good", body: "Useful text", keywords: []),
            Snippet(id: "blank-title", title: "  ", body: "Useful text", keywords: []),
            Snippet(id: "blank-body", title: "No Body", body: "\n ", keywords: []),
        ]

        store.save(snippets)

        XCTAssertEqual(store.snippets(), [
            Snippet(id: "good", title: "Good", body: "Useful text", keywords: []),
        ])
    }

    func testClearRestoresDefaults() {
        let store = SnippetStore(defaults: defaults)
        store.save([
            Snippet(id: "custom", title: "Custom", body: "Body", keywords: []),
        ])

        store.clear()

        XCTAssertEqual(store.snippets().map(\.title), [
            "Email Greeting",
            "Meeting Notes",
            "Bug Report",
            "Thank You",
        ])
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
unless group.files.any? { |f| f.path == 'SnippetStoreTests.swift' }
  ref = group.new_file('SnippetStoreTests.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 3: Run the store tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/SnippetStoreTests
```

Expected: compile failure mentioning missing `Snippet` and `SnippetStore`.

- [ ] **Step 4: Write the store implementation**

Create `platforms/macos/Atlas/SnippetStore.swift`:

```swift
import Foundation

struct Snippet: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let body: String
    let keywords: [String]
}

protocol SnippetProviding {
    func snippets() -> [Snippet]
}

final class SnippetStore: SnippetProviding {
    private static let storageKey = "snippets.items"

    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snippets() -> [Snippet] {
        guard
            let data = defaults.data(forKey: Self.storageKey),
            let snippets = try? decoder.decode([Snippet].self, from: data)
        else {
            return Self.defaultSnippets
        }
        return snippets
    }

    func save(_ snippets: [Snippet]) {
        let cleanSnippets = snippets.filter { snippet in
            !snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !snippet.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let data = try? encoder.encode(cleanSnippets) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    static let defaultSnippets: [Snippet] = [
        Snippet(
            id: "email-greeting",
            title: "Email Greeting",
            body: "Hi,\n\nThanks for reaching out.",
            keywords: ["email", "greeting", "hello"]
        ),
        Snippet(
            id: "meeting-notes",
            title: "Meeting Notes",
            body: "Notes:\n- \n\nNext steps:\n- ",
            keywords: ["meeting", "notes", "agenda"]
        ),
        Snippet(
            id: "bug-report",
            title: "Bug Report",
            body: "Summary:\n\nSteps to reproduce:\n1. \n\nExpected:\n\nActual:",
            keywords: ["bug", "issue", "report"]
        ),
        Snippet(
            id: "thank-you",
            title: "Thank You",
            body: "Thanks, I appreciate it.",
            keywords: ["thanks", "thank you", "reply"]
        ),
    ]
}
```

- [ ] **Step 5: Add the store file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']
unless group.files.any? { |f| f.path == 'SnippetStore.swift' }
  ref = group.new_file('SnippetStore.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 6: Run store tests to verify they pass**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/SnippetStoreTests
```

Expected: `SnippetStoreTests` passes with 5 tests and 0 failures.

- [ ] **Step 7: Commit**

Run:

```bash
git add platforms/macos/Atlas/SnippetStore.swift \
        platforms/macos/AtlasTests/SnippetStoreTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add snippet store"
```

---

## Task 2: Snippets Provider

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/SnippetsProvider.swift`
- Create: `platforms/macos/AtlasTests/SnippetsProviderTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing provider tests**

Create `platforms/macos/AtlasTests/SnippetsProviderTests.swift`:

```swift
import XCTest
@testable import Atlas

final class SnippetsProviderTests: XCTestCase {
    func testEmptyQueryReturnsNoResults() {
        let provider = makeProvider()

        XCTAssertTrue(provider.results(for: " \n ").isEmpty)
    }

    func testSnippetQueryReturnsSnippetCommands() {
        let provider = makeProvider()
        let results = provider.results(for: "snippet")

        XCTAssertEqual(results.map(\.title), [
            "Copy Email Greeting",
            "Copy Bug Report",
        ])
    }

    func testTitleQueryMatchesSnippet() {
        let provider = makeProvider()
        let results = provider.results(for: "meeting")

        XCTAssertEqual(results.map(\.title), ["Copy Meeting Notes"])
    }

    func testBodyQueryMatchesSnippet() {
        let provider = makeProvider()
        let results = provider.results(for: "reproduce")

        XCTAssertEqual(results.map(\.title), ["Copy Bug Report"])
    }

    func testKeywordQueryMatchesSnippet() {
        let provider = makeProvider()
        let results = provider.results(for: "hello")

        XCTAssertEqual(results.map(\.title), ["Copy Email Greeting"])
    }

    func testAllResultsHaveSnippetCategoryAndIcon() {
        let provider = makeProvider()
        let results = provider.results(for: "snippet")

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.category == "Snippet" })
        XCTAssertTrue(results.allSatisfy { $0.icon == .sfSymbol("text.quote") })
    }

    func testExecutingResultCopiesSnippetBodyToClipboard() {
        let clipboard = FakeClipboardReader()
        let provider = makeProvider(clipboard: clipboard)

        let result = provider.results(for: "meeting").first
        if case .execute(let execute)? = result?.action {
            execute()
        } else {
            XCTFail("expected executable snippet result")
        }

        XCTAssertEqual(clipboard.writtenText, "Notes:\n- item")
    }

    func testResultsAreCappedToFive() {
        let snippets = (1...8).map { index in
            Snippet(
                id: "snippet-\(index)",
                title: "Snippet \(index)",
                body: "Body \(index)",
                keywords: ["snippet"]
            )
        }
        let provider = SnippetsProvider(
            snippetProvider: FixedSnippetProvider(snippets: snippets),
            clipboard: FakeClipboardReader()
        )

        XCTAssertEqual(provider.results(for: "snippet").count, 5)
    }

    private func makeProvider(clipboard: FakeClipboardReader = FakeClipboardReader()) -> SnippetsProvider {
        SnippetsProvider(
            snippetProvider: FixedSnippetProvider(snippets: [
                Snippet(
                    id: "email",
                    title: "Email Greeting",
                    body: "Hi there",
                    keywords: ["snippet", "hello"]
                ),
                Snippet(
                    id: "meeting",
                    title: "Meeting Notes",
                    body: "Notes:\n- item",
                    keywords: ["notes"]
                ),
                Snippet(
                    id: "bug",
                    title: "Bug Report",
                    body: "Steps to reproduce",
                    keywords: ["snippet", "bug"]
                ),
            ]),
            clipboard: clipboard
        )
    }
}

private struct FixedSnippetProvider: SnippetProviding {
    let snippets: [Snippet]
}

private final class FakeClipboardReader: ClipboardReading {
    var changeCount: Int = 0
    private(set) var writtenText: String?

    func string() -> String? {
        writtenText
    }

    func setString(_ text: String) {
        writtenText = text
        changeCount += 1
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
unless group.files.any? { |f| f.path == 'SnippetsProviderTests.swift' }
  ref = group.new_file('SnippetsProviderTests.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 3: Run the provider tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/SnippetsProviderTests
```

Expected: compile failure mentioning missing `SnippetsProvider`.

- [ ] **Step 4: Write the provider implementation**

Create `platforms/macos/Atlas/CommandPalette/SnippetsProvider.swift`:

```swift
import Foundation

final class SnippetsProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let snippetProvider: SnippetProviding
    private let clipboard: ClipboardReading

    init(
        snippetProvider: SnippetProviding = SnippetStore(),
        clipboard: ClipboardReading = SystemClipboardReader()
    ) {
        self.snippetProvider = snippetProvider
        self.clipboard = clipboard
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return snippetProvider.snippets()
            .filter { snippet in
                snippet.title.localizedCaseInsensitiveContains(q) ||
                snippet.body.localizedCaseInsensitiveContains(q) ||
                snippet.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
            }
            .prefix(Self.maxResultsCount)
            .map { [clipboard] snippet in
                PaletteCommand(
                    id: UUID(),
                    title: "Copy \(snippet.title)",
                    subtitle: Self.subtitle(for: snippet.body),
                    icon: .sfSymbol("text.quote"),
                    keywords: snippet.keywords + [snippet.title],
                    action: .execute {
                        clipboard.setString(snippet.body)
                    },
                    category: "Snippet"
                )
            }
    }

    private static func subtitle(for body: String) -> String {
        let singleLine = body
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return String(singleLine.prefix(80))
    }
}
```

- [ ] **Step 5: Add the provider file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']['CommandPalette']
unless group.files.any? { |f| f.path == 'SnippetsProvider.swift' }
  ref = group.new_file('SnippetsProvider.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 6: Run provider and store tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/SnippetsProviderTests \
  -only-testing:AtlasTests/SnippetStoreTests
```

Expected: both test classes pass with 13 tests and 0 failures.

- [ ] **Step 7: Commit**

Run:

```bash
git add platforms/macos/Atlas/CommandPalette/SnippetsProvider.swift \
        platforms/macos/AtlasTests/SnippetsProviderTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add command palette snippets provider"
```

---

## Task 3: Register Snippets Provider and Verify

**Files:**
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Test: `platforms/macos/AtlasTests/SnippetsProviderTests.swift`
- Test: `platforms/macos/AtlasTests/SnippetStoreTests.swift`

- [ ] **Step 1: Register `SnippetsProvider`**

In `platforms/macos/Atlas/AtlasApp.swift`, update `CommandPaletteState.init()` provider construction from:

```swift
let developerToolsProvider = DeveloperToolsProvider()
let windowManagementProvider = WindowManagementProvider()
let clipboardHistoryProvider = ClipboardHistoryProvider()
let appLauncherProvider = AppLauncherProvider()

self.controller = CommandPaletteController(providers: [
    atlasProvider,
    developerToolsProvider,
    windowManagementProvider,
    clipboardHistoryProvider,
    appLauncherProvider,
])
```

to:

```swift
let developerToolsProvider = DeveloperToolsProvider()
let windowManagementProvider = WindowManagementProvider()
let clipboardHistoryProvider = ClipboardHistoryProvider()
let snippetsProvider = SnippetsProvider()
let appLauncherProvider = AppLauncherProvider()

self.controller = CommandPaletteController(providers: [
    atlasProvider,
    developerToolsProvider,
    windowManagementProvider,
    clipboardHistoryProvider,
    snippetsProvider,
    appLauncherProvider,
])
```

- [ ] **Step 2: Run focused provider tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/SnippetsProviderTests \
  -only-testing:AtlasTests/SnippetStoreTests \
  -only-testing:AtlasTests/ClipboardHistoryProviderTests \
  -only-testing:AtlasTests/WindowManagementProviderTests \
  -only-testing:AtlasTests/DeveloperToolsProviderTests \
  -only-testing:AtlasTests/AppLauncherProviderTests \
  -only-testing:AtlasTests/AtlasCommandProviderTests
```

Expected: selected tests pass with 66 tests and 0 failures.

- [ ] **Step 3: Run full macOS test suite**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS'
```

Expected: full suite passes. Existing environment warnings about CoreSimulator or `com.apple.linkd.autoShortcut` are non-blocking if the test result ends with `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit registration**

Run:

```bash
git add platforms/macos/Atlas/AtlasApp.swift
git commit -m "feat(macos): register snippet commands"
```

---

## Task 4: Record Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-22-command-palette-snippets-v1.md`

- [ ] **Step 1: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-22-command-palette-snippets-v1.md`:

```markdown
## Verification Notes

Completed on 2026-05-22 on branch `codex/command-palette-snippets-v1`.

- Focused provider/store tests:
  - `SnippetsProviderTests`
  - `SnippetStoreTests`
  - `ClipboardHistoryProviderTests`
  - `WindowManagementProviderTests`
  - `DeveloperToolsProviderTests`
  - `AppLauncherProviderTests`
  - `AtlasCommandProviderTests`
- Full macOS test suite:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Manual snippet copy verification was not run; this follows the project preference that unit tests are sufficient unless explicitly requested.
```

- [ ] **Step 2: Commit the plan and verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-command-palette-snippets-v1.md
git commit -m "docs: add command palette snippets plan"
```

---

## Self-Review

1. **Spec coverage:** This plan adds snippet storage, a command palette provider, clipboard copy execution, provider registration, deterministic tests, and verification notes. Snippet editing UI, rich snippets, shortcut assignment, and sync/import/export remain outside this plan.

2. **Placeholder scan:** The plan contains concrete paths, exact test code, exact implementation code, commands, expected results, and commit messages. It does not use undefined future types before they are introduced.

3. **Type consistency:** `Snippet`, `SnippetProviding`, `SnippetStore`, and `SnippetsProvider` are introduced before later tasks reference them. Provider tests use the existing `ClipboardReading` and `SystemClipboardReader` types from `ClipboardHistoryProvider.swift`.

## Verification Notes

Completed on 2026-05-22 on branch `codex/command-palette-snippets-v1`.

- Focused provider/store tests:
  - `SnippetsProviderTests`
  - `SnippetStoreTests`
  - `ClipboardHistoryProviderTests`
  - `WindowManagementProviderTests`
  - `DeveloperToolsProviderTests`
  - `AppLauncherProviderTests`
  - `AtlasCommandProviderTests`
- Full macOS test suite:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Manual snippet copy verification was not run; this follows the project preference that unit tests are sufficient unless explicitly requested.
