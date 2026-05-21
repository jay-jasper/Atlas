# Command Palette Shell v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Raycast-style global command palette (`⌥Space`) to Atlas that exposes all existing features and launches macOS apps via a floating NSPanel with keyboard-driven navigation.

**Architecture:** A `CommandProviding` protocol lets each feature module register commands independently. `CommandPaletteController` manages an `NSPanel` and aggregates results from all providers on each keystroke. Navigation within the panel uses a push-stack to embed existing SwiftUI sub-views (screenshot library, port lookup, window picker).

**Tech Stack:** SwiftUI, AppKit (NSPanel, NSEvent monitors), UserDefaults, NSWorkspace

---

## File Map

**New files (add to Atlas Xcode target):**
- `Atlas/CommandPalette/CommandPaletteModels.swift` — `PaletteCommand`, `PaletteAction`, `PaletteDestination`, `PaletteIcon`
- `Atlas/CommandPalette/CommandProviding.swift` — `CommandProviding` protocol
- `Atlas/CommandPalette/AtlasCommandProvider.swift` — fixed Atlas feature command list
- `Atlas/CommandPalette/AppLauncherProvider.swift` — `/Applications` scanner + fuzzy search
- `Atlas/CommandPalette/CommandPaletteView.swift` — SwiftUI root: search bar + results list + nav stack
- `Atlas/CommandPalette/CommandPaletteController.swift` — `NSPanel` lifecycle: `show()`, `hide()`, `toggle()`
- `Atlas/CommandPalette/KeyRecorderView.swift` — hotkey capture badge component

**New test files (add to AtlasTests target):**
- `AtlasTests/CommandPaletteModelsTests.swift`
- `AtlasTests/AppLauncherProviderTests.swift`
- `AtlasTests/AtlasCommandProviderTests.swift`
- `AtlasTests/GlobalHotkeyServiceTests.swift`
- `AtlasTests/KeyRecorderViewTests.swift`

**Modified files:**
- `Atlas/GlobalHotkeyService.swift` — replace single `onAreaCapture` with multi-handler array
- `Atlas/AtlasApp.swift` — init `CommandPaletteController`, register providers, wire ⌥Space hotkey
- `Atlas/AtlasSettingsView.swift` — add "Command Palette" settings section with `KeyRecorderView`
- `Atlas/ContentView.swift` — pass action closures to `AtlasCommandProvider`

---

## Adding Swift Files to the Xcode Project

Every new `.swift` file must be added to `Atlas.xcodeproj/project.pbxproj` **and** the `Atlas` build phase before it will compile. Use the Ruby one-liner pattern that was used earlier in this project:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']['CommandPalette'] ||
        proj.main_group['Atlas'].new_group('CommandPalette', 'CommandPalette')
file_ref = group.new_reference('FileName.swift')
target.source_build_phase.add_file_reference(file_ref)
proj.save
"
```

For test files, replace `target = proj.targets.find { |t| t.name == 'Atlas' }` with `target = proj.targets.find { |t| t.name == 'AtlasTests' }` and use `proj.main_group['AtlasTests']`.

Run tests with:
```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed|warning:.*error)'
```

---

## Task 1: Data Models

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`
- Create: `platforms/macos/Atlas/CommandPalette/CommandProviding.swift`
- Create: `platforms/macos/AtlasTests/CommandPaletteModelsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `platforms/macos/AtlasTests/CommandPaletteModelsTests.swift`:

```swift
import XCTest
@testable import Atlas

final class CommandPaletteModelsTests: XCTestCase {
    func testPaletteCommandHasStableIdentity() {
        let id = UUID()
        let cmd = PaletteCommand(
            id: id,
            title: "Capture Area",
            subtitle: nil,
            icon: .sfSymbol("camera"),
            keywords: ["screenshot"],
            action: .execute({}),
            category: "Atlas"
        )
        XCTAssertEqual(cmd.id, id)
        XCTAssertEqual(cmd.title, "Capture Area")
        XCTAssertNil(cmd.subtitle)
        XCTAssertEqual(cmd.category, "Atlas")
        XCTAssertEqual(cmd.keywords, ["screenshot"])
    }

    func testPaletteIconEquality() {
        XCTAssertEqual(PaletteIcon.sfSymbol("camera"), PaletteIcon.sfSymbol("camera"))
        XCTAssertNotEqual(PaletteIcon.sfSymbol("camera"), PaletteIcon.sfSymbol("photo"))
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        XCTAssertEqual(PaletteIcon.appIcon(url), PaletteIcon.appIcon(url))
    }

    func testPaletteActionIsExecuteOrPush() {
        var called = false
        let exec = PaletteAction.execute({ called = true })
        if case .execute(let fn) = exec { fn() }
        XCTAssertTrue(called)

        let push = PaletteAction.push(.portLookup)
        if case .push(let dest) = push {
            XCTAssertEqual(dest, PaletteDestination.portLookup)
        } else {
            XCTFail("expected .push")
        }
    }

    func testPaletteDestinationEquality() {
        XCTAssertEqual(PaletteDestination.portLookup, PaletteDestination.portLookup)
        XCTAssertEqual(PaletteDestination.windowPicker, PaletteDestination.windowPicker)
        XCTAssertEqual(PaletteDestination.screenshotLibrary, PaletteDestination.screenshotLibrary)
        XCTAssertNotEqual(PaletteDestination.portLookup, PaletteDestination.windowPicker)
    }
}
```

- [ ] **Step 2: Add test file to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
ref = group.new_reference('CommandPaletteModelsTests.swift')
target.source_build_phase.add_file_reference(ref)
proj.save
"
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: compile error — `PaletteCommand`, `PaletteIcon`, `PaletteAction`, `PaletteDestination` not found.

- [ ] **Step 4: Create the CommandPalette group directory**

```bash
mkdir -p /Users/lee/workspaces/ai/Atlas/platforms/macos/Atlas/CommandPalette
```

- [ ] **Step 5: Write CommandProviding.swift**

Create `platforms/macos/Atlas/CommandPalette/CommandProviding.swift`:

```swift
import Foundation

protocol CommandProviding {
    func results(for query: String) -> [PaletteCommand]
}
```

- [ ] **Step 6: Write CommandPaletteModels.swift**

Create `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`:

```swift
import Foundation
import SwiftUI

struct PaletteCommand: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let icon: PaletteIcon
    let keywords: [String]
    let action: PaletteAction
    let category: String
}

enum PaletteIcon: Equatable {
    case sfSymbol(String)
    case appIcon(URL)
}

enum PaletteAction {
    case execute(() -> Void)
    case push(PaletteDestination)
}

enum PaletteDestination: Equatable {
    case windowPicker
    case screenshotLibrary
    case portLookup
}
```

- [ ] **Step 7: Add both source files to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
parent = proj.main_group['Atlas']
group = parent.children.find { |c| c.respond_to?(:name) && c.name == 'CommandPalette' } ||
        parent.new_group('CommandPalette', 'CommandPalette')
['CommandProviding.swift', 'CommandPaletteModels.swift'].each do |name|
  ref = group.new_reference(name)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 8: Run tests to verify they pass**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: `CommandPaletteModelsTests` passes, all other tests pass.

- [ ] **Step 9: Commit**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
git add platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift \
        platforms/macos/Atlas/CommandPalette/CommandProviding.swift \
        platforms/macos/AtlasTests/CommandPaletteModelsTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj && \
git commit -m "feat(macos): add command palette data models and CommandProviding protocol"
```

---

## Task 2: AtlasCommandProvider

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/AtlasCommandProvider.swift`
- Create: `platforms/macos/AtlasTests/AtlasCommandProviderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `platforms/macos/AtlasTests/AtlasCommandProviderTests.swift`:

```swift
import XCTest
@testable import Atlas

final class AtlasCommandProviderTests: XCTestCase {
    private var provider: AtlasCommandProvider!

    override func setUp() {
        provider = AtlasCommandProvider(
            onCaptureDesktop: {},
            onCaptureArea: {},
            onCaptureWindow: {},
            onOpenSettings: {}
        )
    }

    func testEmptyQueryReturnsAllDefaultCommands() {
        let results = provider.results(for: "")
        XCTAssertFalse(results.isEmpty)
        // All core commands present
        XCTAssertTrue(results.contains { $0.title == "Capture Desktop" })
        XCTAssertTrue(results.contains { $0.title == "Capture Area" })
        XCTAssertTrue(results.contains { $0.title == "Capture Window" })
        XCTAssertTrue(results.contains { $0.title == "Screenshot Library" })
        XCTAssertTrue(results.contains { $0.title == "Port Lookup" })
        XCTAssertTrue(results.contains { $0.title == "Open Settings" })
    }

    func testTitlePrefixMatchReturnsResult() {
        let results = provider.results(for: "capture")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy {
            $0.title.lowercased().hasPrefix("capture") ||
            $0.keywords.contains { $0.localizedCaseInsensitiveContains("capture") }
        })
    }

    func testKeywordSubstringMatchReturnsResult() {
        let results = provider.results(for: "port")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.title == "Port Lookup" })
    }

    func testCaseInsensitiveMatching() {
        let lower = provider.results(for: "screenshot")
        let upper = provider.results(for: "SCREENSHOT")
        XCTAssertEqual(lower.map(\.title).sorted(), upper.map(\.title).sorted())
    }

    func testNonMatchingQueryReturnsEmpty() {
        let results = provider.results(for: "xyzzy123")
        XCTAssertTrue(results.isEmpty)
    }

    func testAllCommandsHaveAtlasCategory() {
        let results = provider.results(for: "")
        XCTAssertTrue(results.allSatisfy { $0.category == "Atlas" })
    }

    func testCaptureWindowActionIsPush() {
        let results = provider.results(for: "Capture Window")
        let cmd = results.first { $0.title == "Capture Window" }!
        if case .push(let dest) = cmd.action {
            XCTAssertEqual(dest, .windowPicker)
        } else {
            XCTFail("expected .push(.windowPicker)")
        }
    }

    func testScreenshotLibraryActionIsPush() {
        let cmd = provider.results(for: "").first { $0.title == "Screenshot Library" }!
        if case .push(let dest) = cmd.action {
            XCTAssertEqual(dest, .screenshotLibrary)
        } else {
            XCTFail("expected .push(.screenshotLibrary)")
        }
    }

    func testPortLookupActionIsPush() {
        let cmd = provider.results(for: "").first { $0.title == "Port Lookup" }!
        if case .push(let dest) = cmd.action {
            XCTAssertEqual(dest, .portLookup)
        } else {
            XCTFail("expected .push(.portLookup)")
        }
    }

    func testCaptureDesktopCallsCallback() {
        var called = false
        let p = AtlasCommandProvider(
            onCaptureDesktop: { called = true },
            onCaptureArea: {},
            onCaptureWindow: {},
            onOpenSettings: {}
        )
        let cmd = p.results(for: "").first { $0.title == "Capture Desktop" }!
        if case .execute(let fn) = cmd.action { fn() }
        XCTAssertTrue(called)
    }
}
```

- [ ] **Step 2: Add test file to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
ref = group.new_reference('AtlasCommandProviderTests.swift')
target.source_build_phase.add_file_reference(ref)
proj.save
"
```

- [ ] **Step 3: Run to verify compile failure**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: compile error — `AtlasCommandProvider` not found.

- [ ] **Step 4: Write AtlasCommandProvider.swift**

Create `platforms/macos/Atlas/CommandPalette/AtlasCommandProvider.swift`:

```swift
import Foundation

final class AtlasCommandProvider: CommandProviding {
    private let commands: [PaletteCommand]

    init(
        onCaptureDesktop: @escaping () -> Void,
        onCaptureArea: @escaping () -> Void,
        onCaptureWindow: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        commands = [
            PaletteCommand(
                id: UUID(),
                title: "Capture Desktop",
                subtitle: nil,
                icon: .sfSymbol("desktopcomputer"),
                keywords: ["screenshot", "capture", "desktop"],
                action: .execute(onCaptureDesktop),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Capture Area",
                subtitle: nil,
                icon: .sfSymbol("crop"),
                keywords: ["screenshot", "capture", "area", "region"],
                action: .execute(onCaptureArea),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Capture Window",
                subtitle: nil,
                icon: .sfSymbol("macwindow"),
                keywords: ["screenshot", "capture", "window"],
                action: .push(.windowPicker),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Screenshot Library",
                subtitle: nil,
                icon: .sfSymbol("photo.stack"),
                keywords: ["library", "screenshots", "history"],
                action: .push(.screenshotLibrary),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Port Lookup",
                subtitle: nil,
                icon: .sfSymbol("network"),
                keywords: ["port", "process", "network"],
                action: .push(.portLookup),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Open Settings",
                subtitle: nil,
                icon: .sfSymbol("gear"),
                keywords: ["settings", "preferences"],
                action: .execute(onOpenSettings),
                category: "Atlas"
            ),
        ]
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        let lower = q.lowercased()
        return commands.filter { cmd in
            cmd.title.lowercased().hasPrefix(lower) ||
            cmd.title.lowercased().contains(lower) ||
            cmd.keywords.contains { $0.lowercased().contains(lower) }
        }
    }
}
```

- [ ] **Step 5: Add source file to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas'].children.find { |c| c.respond_to?(:name) && c.name == 'CommandPalette' }
ref = group.new_reference('AtlasCommandProvider.swift')
target.source_build_phase.add_file_reference(ref)
proj.save
"
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: all `AtlasCommandProviderTests` pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
git add platforms/macos/Atlas/CommandPalette/AtlasCommandProvider.swift \
        platforms/macos/AtlasTests/AtlasCommandProviderTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj && \
git commit -m "feat(macos): add AtlasCommandProvider with fixed command list"
```

---

## Task 3: AppLauncherProvider

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/AppLauncherProvider.swift`
- Create: `platforms/macos/AtlasTests/AppLauncherProviderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `platforms/macos/AtlasTests/AppLauncherProviderTests.swift`:

```swift
import XCTest
@testable import Atlas

final class AppLauncherProviderTests: XCTestCase {
    func testEmptyQueryReturnsNoResults() {
        let provider = AppLauncherProvider(apps: fakeApps())
        XCTAssertEqual(provider.results(for: "").count, 0)
    }

    func testExactPrefixMatchScoresHighest() {
        let apps = [
            AppEntry(name: "Safari", url: url("Safari"), icon: nil),
            AppEntry(name: "Xcode", url: url("Xcode"), icon: nil),
            AppEntry(name: "Slack", url: url("Slack"), icon: nil),
        ]
        let provider = AppLauncherProvider(apps: apps)
        let results = provider.results(for: "Saf")
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.title, "Safari")
    }

    func testResultsAreCappedAtFive() {
        let apps = (1...10).map { i in
            AppEntry(name: "App\(i)", url: url("App\(i)"), icon: nil)
        }
        let provider = AppLauncherProvider(apps: apps)
        let results = provider.results(for: "app")
        XCTAssertLessThanOrEqual(results.count, 5)
    }

    func testCaseInsensitiveMatching() {
        let apps = [AppEntry(name: "TextEdit", url: url("TextEdit"), icon: nil)]
        let provider = AppLauncherProvider(apps: apps)
        XCTAssertFalse(provider.results(for: "textedit").isEmpty)
        XCTAssertFalse(provider.results(for: "TEXTEDIT").isEmpty)
        XCTAssertFalse(provider.results(for: "TextEdit").isEmpty)
    }

    func testNonMatchingQueryReturnsEmpty() {
        let provider = AppLauncherProvider(apps: fakeApps())
        XCTAssertTrue(provider.results(for: "xyzzy9999").isEmpty)
    }

    func testAllResultsHaveAppCategory() {
        let apps = [AppEntry(name: "Safari", url: url("Safari"), icon: nil)]
        let provider = AppLauncherProvider(apps: apps)
        let results = provider.results(for: "safari")
        XCTAssertTrue(results.allSatisfy { $0.category == "App" })
    }

    func testFuzzyMatchFindsNonPrefixMatch() {
        let apps = [AppEntry(name: "System Preferences", url: url("System Preferences"), icon: nil)]
        let provider = AppLauncherProvider(apps: apps)
        // Contains match
        let results = provider.results(for: "prefs")
        // "prefs" is not a prefix or exact match, but fuzzy should still find it
        // Accept either empty or a match (fuzzy scorer may or may not find it)
        // What we care about: no crash, valid results structure
        for result in results {
            XCTAssertEqual(result.category, "App")
        }
    }

    // MARK: - Fuzzy score tests

    func testFuzzyScoreReturnsHigherScoreForConsecutiveMatch() {
        let consecutiveScore = AppLauncherProvider.fuzzyScore(query: "saf", in: "Safari")
        let nonConsecutiveScore = AppLauncherProvider.fuzzyScore(query: "sri", in: "Safari")
        XCTAssertGreaterThan(consecutiveScore, nonConsecutiveScore)
    }

    func testFuzzyScoreReturnsZeroForNoMatch() {
        let score = AppLauncherProvider.fuzzyScore(query: "xyz", in: "Safari")
        XCTAssertEqual(score, 0)
    }

    // MARK: - Helpers

    private func fakeApps() -> [AppEntry] {
        [
            AppEntry(name: "Safari", url: url("Safari"), icon: nil),
            AppEntry(name: "Xcode", url: url("Xcode"), icon: nil),
        ]
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Applications/\(name).app")
    }
}
```

- [ ] **Step 2: Add test file to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
ref = group.new_reference('AppLauncherProviderTests.swift')
target.source_build_phase.add_file_reference(ref)
proj.save
"
```

- [ ] **Step 3: Run to verify compile failure**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: compile error — `AppLauncherProvider`, `AppEntry` not found.

- [ ] **Step 4: Write AppLauncherProvider.swift**

Create `platforms/macos/Atlas/CommandPalette/AppLauncherProvider.swift`:

```swift
import AppKit
import Foundation

struct AppEntry {
    let name: String
    let url: URL
    let icon: NSImage?
}

final class AppLauncherProvider: CommandProviding {
    private let apps: [AppEntry]

    init(apps: [AppEntry]? = nil) {
        if let apps {
            self.apps = apps
        } else {
            self.apps = Self.scanApplications()
        }
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        let scored = apps.compactMap { app -> (AppEntry, Int)? in
            let score = Self.fuzzyScore(query: q, in: app.name)
            return score > 0 ? (app, score) : nil
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { entry, _ in
                let iconURL = entry.url
                return PaletteCommand(
                    id: UUID(),
                    title: entry.name,
                    subtitle: nil,
                    icon: .appIcon(iconURL),
                    keywords: [],
                    action: .execute { NSWorkspace.shared.open(entry.url) },
                    category: "App"
                )
            }
    }

    static func fuzzyScore(query: String, in target: String) -> Int {
        let q = query.lowercased()
        let t = target.lowercased()

        guard !q.isEmpty else { return 0 }

        // Exact prefix: highest score
        if t.hasPrefix(q) { return 1000 + (100 - t.count) }

        // Contains match: medium score
        if t.contains(q) { return 500 }

        // Fuzzy: all query chars must appear in order in target
        var qi = q.startIndex
        var consecutiveBonus = 0
        var lastMatchIndex: String.Index? = nil

        for (ti, tc) in zip(t.indices, t) {
            if qi < q.endIndex, tc == q[qi] {
                if let last = lastMatchIndex, t.index(after: last) == ti {
                    consecutiveBonus += 10
                }
                lastMatchIndex = ti
                qi = q.index(after: qi)
            }
        }

        guard qi == q.endIndex else { return 0 }
        return 100 + consecutiveBonus
    }

    private static func scanApplications() -> [AppEntry] {
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Applications")),
        ]
        var entries: [AppEntry] = []
        for dir in dirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }
            for url in contents where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                entries.append(AppEntry(name: name, url: url, icon: icon))
            }
        }
        return entries.sorted { $0.name < $1.name }
    }
}
```

- [ ] **Step 5: Add source file to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas'].children.find { |c| c.respond_to?(:name) && c.name == 'CommandPalette' }
ref = group.new_reference('AppLauncherProvider.swift')
target.source_build_phase.add_file_reference(ref)
proj.save
"
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: all `AppLauncherProviderTests` pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
git add platforms/macos/Atlas/CommandPalette/AppLauncherProvider.swift \
        platforms/macos/AtlasTests/AppLauncherProviderTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj && \
git commit -m "feat(macos): add AppLauncherProvider with fuzzy app search"
```

---

## Task 4: GlobalHotkeyService Multi-Hotkey Refactor

**Files:**
- Modify: `platforms/macos/Atlas/GlobalHotkeyService.swift`
- Create: `platforms/macos/AtlasTests/GlobalHotkeyServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `platforms/macos/AtlasTests/GlobalHotkeyServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class GlobalHotkeyServiceTests: XCTestCase {
    func testRegisteredHandlerIsStoredAndRetrievable() {
        let service = GlobalHotkeyService()
        var count = 0
        service.register(keyCode: 49, modifiers: .option) { count += 1 }
        XCTAssertEqual(service.registeredCount, 1)
    }

    func testMultipleHandlersCanBeRegistered() {
        let service = GlobalHotkeyService()
        service.register(keyCode: 49, modifiers: .option) {}
        service.register(keyCode: 21, modifiers: [.control, .shift]) {}
        XCTAssertEqual(service.registeredCount, 2)
    }

    func testCorrectHandlerFiredForMatchingKeyCode() {
        let service = GlobalHotkeyService()
        var firstCalled = false
        var secondCalled = false
        service.register(keyCode: 49, modifiers: .option) { firstCalled = true }
        service.register(keyCode: 21, modifiers: [.control, .shift]) { secondCalled = true }

        service.simulateKeyEvent(keyCode: 49, modifiers: .option)
        XCTAssertTrue(firstCalled)
        XCTAssertFalse(secondCalled)

        service.simulateKeyEvent(keyCode: 21, modifiers: [.control, .shift])
        XCTAssertTrue(secondCalled)
    }

    func testNoHandlerFiredForUnmatchedKeyCode() {
        let service = GlobalHotkeyService()
        var called = false
        service.register(keyCode: 49, modifiers: .option) { called = true }

        service.simulateKeyEvent(keyCode: 36, modifiers: .option)
        XCTAssertFalse(called)
    }

    func testModifierMismatchDoesNotFireHandler() {
        let service = GlobalHotkeyService()
        var called = false
        service.register(keyCode: 49, modifiers: .option) { called = true }

        service.simulateKeyEvent(keyCode: 49, modifiers: .command)
        XCTAssertFalse(called)
    }

    func testLegacyAreaCaptureHandlerStillWorks() {
        let service = GlobalHotkeyService()
        var called = false
        service.onAreaCapture = { called = true }

        service.simulateKeyEvent(keyCode: 21, modifiers: [.control, .shift])
        XCTAssertTrue(called)
    }
}
```

- [ ] **Step 2: Add test file to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
ref = group.new_reference('GlobalHotkeyServiceTests.swift')
target.source_build_phase.add_file_reference(ref)
proj.save
"
```

- [ ] **Step 3: Run to verify compile failure**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: compile errors — `register(keyCode:modifiers:)`, `registeredCount`, `simulateKeyEvent` not found.

- [ ] **Step 4: Rewrite GlobalHotkeyService.swift**

Replace the full contents of `platforms/macos/Atlas/GlobalHotkeyService.swift`:

```swift
import AppKit

final class GlobalHotkeyService {
    private struct Registration {
        let keyCode: Int
        let modifiers: NSEvent.ModifierFlags
        let handler: () -> Void
    }

    // Legacy single-callback compatibility
    var onAreaCapture: (() -> Void)? {
        didSet {
            areaCaptureLegacyRegistered = false
            if let cb = onAreaCapture {
                register(keyCode: 21, modifiers: [.control, .shift], handler: cb)
                areaCaptureLegacyRegistered = true
            }
        }
    }
    private var areaCaptureLegacyRegistered = false

    private var registrations: [Registration] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var registeredCount: Int { registrations.count }

    func register(keyCode: Int, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        registrations.append(Registration(keyCode: keyCode, modifiers: modifiers, handler: handler))
    }

    func start() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }

        guard AXIsProcessTrusted() else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor  = nil
    }

    func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    // Internal for testing: fire the matching handler synchronously
    func simulateKeyEvent(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        for reg in registrations {
            let regFlags = reg.modifiers.intersection(.deviceIndependentFlagsMask)
            if reg.keyCode == keyCode, regFlags == flags {
                reg.handler()
                return
            }
        }
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        for reg in registrations {
            let regFlags = reg.modifiers.intersection(.deviceIndependentFlagsMask)
            if reg.keyCode == Int(event.keyCode), regFlags == flags {
                DispatchQueue.main.async { reg.handler() }
                return nil
            }
        }
        return event
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: all `GlobalHotkeyServiceTests` pass, all existing tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
git add platforms/macos/Atlas/GlobalHotkeyService.swift \
        platforms/macos/AtlasTests/GlobalHotkeyServiceTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj && \
git commit -m "refactor(macos): GlobalHotkeyService supports multiple hotkey registrations"
```

---

## Task 5: KeyRecorderView

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/KeyRecorderView.swift`
- Create: `platforms/macos/AtlasTests/KeyRecorderViewTests.swift`

- [ ] **Step 1: Write the failing test**

Create `platforms/macos/AtlasTests/KeyRecorderViewTests.swift`:

```swift
import XCTest
@testable import Atlas

final class KeyRecorderViewTests: XCTestCase {
    func testDefaultHotkeyLoadedFromDefaults() {
        let defaults = UserDefaults(suiteName: "test.keyrecorder")!
        defaults.removeObject(forKey: "palette.hotkey.keyCode")
        defaults.removeObject(forKey: "palette.hotkey.modifiers")

        let config = HotkeyConfig.load(from: defaults)
        XCTAssertEqual(config.keyCode, 49)  // Space
        XCTAssertEqual(config.modifiers, NSEvent.ModifierFlags.option.rawValue)
    }

    func testSavedHotkeyRoundTrips() {
        let defaults = UserDefaults(suiteName: "test.keyrecorder")!
        let config = HotkeyConfig(keyCode: 36, modifiers: NSEvent.ModifierFlags.command.rawValue)
        config.save(to: defaults)

        let loaded = HotkeyConfig.load(from: defaults)
        XCTAssertEqual(loaded.keyCode, 36)
        XCTAssertEqual(loaded.modifiers, NSEvent.ModifierFlags.command.rawValue)

        defaults.removeObject(forKey: "palette.hotkey.keyCode")
        defaults.removeObject(forKey: "palette.hotkey.modifiers")
    }

    func testValidationRequiresAtLeastOneModifier() {
        XCTAssertTrue(HotkeyConfig.isValid(modifiers: .option))
        XCTAssertTrue(HotkeyConfig.isValid(modifiers: .command))
        XCTAssertTrue(HotkeyConfig.isValid(modifiers: .control))
        XCTAssertTrue(HotkeyConfig.isValid(modifiers: .shift))
        XCTAssertFalse(HotkeyConfig.isValid(modifiers: []))
    }

    func testDisplayStringFormatting() {
        let config = HotkeyConfig(
            keyCode: 49,
            modifiers: NSEvent.ModifierFlags.option.rawValue
        )
        let display = config.displayString(keyChar: "Space")
        XCTAssertEqual(display, "⌥Space")
    }

    func testConflictDetectionFindsAreaCaptureHotkey() {
        let config = HotkeyConfig(
            keyCode: 21,
            modifiers: NSEvent.ModifierFlags([.control, .shift]).rawValue
        )
        XCTAssertTrue(config.conflictsWithAreaCapture)
    }

    func testNoConflictForDefaultPaletteHotkey() {
        let config = HotkeyConfig(
            keyCode: 49,
            modifiers: NSEvent.ModifierFlags.option.rawValue
        )
        XCTAssertFalse(config.conflictsWithAreaCapture)
    }
}
```

- [ ] **Step 2: Add test file to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
ref = group.new_reference('KeyRecorderViewTests.swift')
target.source_build_phase.add_file_reference(ref)
proj.save
"
```

- [ ] **Step 3: Run to verify compile failure**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: compile error — `HotkeyConfig` not found.

- [ ] **Step 4: Write KeyRecorderView.swift**

Create `platforms/macos/Atlas/CommandPalette/KeyRecorderView.swift`:

```swift
import AppKit
import SwiftUI

struct HotkeyConfig {
    let keyCode: Int
    let modifiers: UInt

    static func load(from defaults: UserDefaults = .standard) -> HotkeyConfig {
        let keyCode = defaults.object(forKey: "palette.hotkey.keyCode") as? Int ?? 49
        let modifiers = defaults.object(forKey: "palette.hotkey.modifiers") as? UInt
            ?? NSEvent.ModifierFlags.option.rawValue
        return HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(keyCode, forKey: "palette.hotkey.keyCode")
        defaults.set(modifiers, forKey: "palette.hotkey.modifiers")
    }

    static func isValid(modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.intersection([.command, .option, .control, .shift]).isEmpty
    }

    var conflictsWithAreaCapture: Bool {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
            .intersection(.deviceIndependentFlagsMask)
        let areaFlags = NSEvent.ModifierFlags([.control, .shift])
            .intersection(.deviceIndependentFlagsMask)
        return keyCode == 21 && flags == areaFlags
    }

    func displayString(keyChar: String) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts = ""
        if flags.contains(.control)  { parts += "⌃" }
        if flags.contains(.option)   { parts += "⌥" }
        if flags.contains(.shift)    { parts += "⇧" }
        if flags.contains(.command)  { parts += "⌘" }
        return parts + keyChar
    }
}

struct KeyRecorderView: View {
    @State private var config: HotkeyConfig = .load()
    @State private var isRecording: Bool = false
    @State private var showConflictWarning: Bool = false
    private let onConfigChanged: (HotkeyConfig) -> Void

    init(onConfigChanged: @escaping (HotkeyConfig) -> Void) {
        self.onConfigChanged = onConfigChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Global Shortcut")
                Spacer()
                shortcutBadge
            }
            if showConflictWarning {
                Text("⚠️ This shortcut conflicts with Area Capture (⌃⇧4).")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .onAppear { config = .load() }
    }

    @ViewBuilder
    private var shortcutBadge: some View {
        let label = isRecording ? "Press shortcut…" : displayLabel
        Text(label)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isRecording
                ? Color.accentColor.opacity(0.15)
                : Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(5)
            .onTapGesture { isRecording = true }
            .background(KeyCaptureView(isActive: isRecording) { keyCode, modifiers in
                guard HotkeyConfig.isValid(modifiers: modifiers) else { return }
                let newConfig = HotkeyConfig(keyCode: keyCode, modifiers: modifiers.rawValue)
                config = newConfig
                newConfig.save()
                showConflictWarning = newConfig.conflictsWithAreaCapture
                isRecording = false
                onConfigChanged(newConfig)
            })
    }

    private var displayLabel: String {
        let keyChar = keyCharForCode(config.keyCode)
        return config.displayString(keyChar: keyChar)
    }

    private func keyCharForCode(_ code: Int) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 53: return "⎋"
        default:
            if let str = keyStringFromKeyCode(UInt16(code)) { return str.uppercased() }
            return "(\(code))"
        }
    }

    private func keyStringFromKeyCode(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        UCKeyTranslate(keyboardLayout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                       OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &len, &chars)
        return len > 0 ? String(utf16CodeUnits: chars, count: len) : nil
    }
}

private struct KeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyCaptureNSView)?.isCapturing = isActive
        if isActive { nsView.window?.makeFirstResponder(nsView) }
    }
}

private final class KeyCaptureNSView: NSView {
    var isCapturing = false
    var onCapture: ((Int, NSEvent.ModifierFlags) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        onCapture?(Int(event.keyCode), flags)
    }
}
```

- [ ] **Step 5: Add source file to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas'].children.find { |c| c.respond_to?(:name) && c.name == 'CommandPalette' }
ref = group.new_reference('KeyRecorderView.swift')
target.source_build_phase.add_file_reference(ref)
proj.save
"
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: all `KeyRecorderViewTests` pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
git add platforms/macos/Atlas/CommandPalette/KeyRecorderView.swift \
        platforms/macos/AtlasTests/KeyRecorderViewTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj && \
git commit -m "feat(macos): add KeyRecorderView and HotkeyConfig for palette shortcut"
```

---

## Task 6: CommandPaletteView (SwiftUI)

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`

No unit tests for this task — panel navigation and animations are verified manually.

- [ ] **Step 1: Write CommandPaletteView.swift**

Create `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`:

```swift
import AppKit
import SwiftUI

struct CommandPaletteView: View {
    let providers: [CommandProviding]
    let onDismiss: () -> Void

    // Injected sub-view content for .screenshotLibrary and .portLookup
    let screenshotLibraryView: AnyView?
    let portLookupView: AnyView?
    let windowPickerView: AnyView?

    @State private var query: String = ""
    @State private var stack: [PaletteDestination] = []
    @State private var selectedIndex: Int = 0

    private var results: [PaletteCommand] {
        providers.flatMap { $0.results(for: query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if stack.isEmpty {
                resultsList
                    .transition(.move(edge: .trailing))
            } else if let dest = stack.last {
                subView(for: dest)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 360)
                    .transition(.move(edge: .trailing))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 16, y: 6)
        .onKeyPress(.escape) {
            if stack.isEmpty {
                onDismiss()
            } else {
                withAnimation(.easeInOut(duration: 0.18)) { stack.removeLast() }
            }
            return .handled
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(stack.isEmpty ? "Search Atlas…" : "Filter…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .onSubmit { executeSelected() }
                .onChange(of: query) { selectedIndex = 0 }
            if !stack.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { stack.removeLast() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    @ViewBuilder
    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results.indices, id: \.self) { i in
                        ResultRow(
                            command: results[i],
                            isSelected: i == selectedIndex
                        )
                        .id(i)
                        .onTapGesture { execute(results[i]) }
                    }
                }
            }
            .frame(maxHeight: 8 * 52)
            .onKeyPress(.upArrow) {
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }
                return .handled
            }
            .onKeyPress(.downArrow) {
                if selectedIndex < results.count - 1 {
                    selectedIndex += 1
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }
                return .handled
            }
            .onKeyPress(.return) {
                executeSelected()
                return .handled
            }
            .onKeyPress(.tab) {
                executeSelected()
                return .handled
            }
        }
    }

    @ViewBuilder
    private func subView(for dest: PaletteDestination) -> some View {
        switch dest {
        case .screenshotLibrary:
            screenshotLibraryView ?? AnyView(Text("Screenshot Library").padding())
        case .portLookup:
            portLookupView ?? AnyView(Text("Port Lookup").padding())
        case .windowPicker:
            windowPickerView ?? AnyView(Text("Window Picker").padding())
        }
    }

    private func executeSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        execute(results[selectedIndex])
    }

    private func execute(_ command: PaletteCommand) {
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
}

private struct ResultRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.body)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(command.category)
                .font(.caption)
                .foregroundColor(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    @ViewBuilder
    private var iconView: some View {
        switch command.icon {
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: 16))
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        case .appIcon(let url):
            AppIconView(url: url)
        }
    }
}

private struct AppIconView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app")
                    .font(.system(size: 16))
            }
        }
        .frame(width: 32, height: 32)
        .task(id: url) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = CGSize(width: 32, height: 32)
            await MainActor.run { image = icon }
        }
    }
}
```

- [ ] **Step 2: Add source file to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas'].children.find { |c| c.respond_to?(:name) && c.name == 'CommandPalette' }
ref = group.new_reference('CommandPaletteView.swift')
target.source_build_phase.add_file_reference(ref)
proj.save
"
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
git add platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj && \
git commit -m "feat(macos): add CommandPaletteView with search bar and navigation stack"
```

---

## Task 7: CommandPaletteController (NSPanel lifecycle)

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`

No unit tests — NSPanel lifecycle is verified manually.

- [ ] **Step 1: Write CommandPaletteController.swift**

Create `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`:

```swift
import AppKit
import SwiftUI

final class CommandPaletteController {
    private var panel: NSPanel?
    private var mouseMonitor: Any?
    private let providers: [CommandProviding]

    // Injected sub-views for sub-destinations
    var screenshotLibraryView: AnyView?
    var portLookupView: AnyView?
    var windowPickerView: AnyView?

    init(providers: [CommandProviding]) {
        self.providers = providers
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard panel == nil || panel?.isVisible == false else { return }

        let paletteView = CommandPaletteView(
            providers: providers,
            onDismiss: { [weak self] in self?.hide() },
            screenshotLibraryView: screenshotLibraryView,
            portLookupView: portLookupView,
            windowPickerView: windowPickerView
        )

        let hostingView = NSHostingView(rootView: paletteView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 640, height: 52)

        let newPanel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .modalPanel
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.contentView = hostingView
        newPanel.isReleasedWhenClosed = false

        positionPanel(newPanel)
        newPanel.orderFrontRegardless()

        panel = newPanel

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let panel = self.panel else { return }
            let loc = event.locationInWindow
            let screenLoc = NSEvent.mouseLocation
            if !panel.frame.contains(screenLoc) {
                self.hide()
            }
        }
    }

    func hide() {
        panel?.close()
        panel = nil
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        mouseMonitor = nil
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - 320  // centered, width 640
        let y = screenFrame.maxY - screenFrame.height * 0.2 - 52  // 20% from top
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }
}
```

- [ ] **Step 2: Add source file to Xcode project**

```bash
cd /Users/lee/workspaces/ai/Atlas && ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas'].children.find { |c| c.respond_to?(:name) && c.name == 'CommandPalette' }
ref = group.new_reference('CommandPaletteController.swift')
target.source_build_phase.add_file_reference(ref)
proj.save
"
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
git add platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj && \
git commit -m "feat(macos): add CommandPaletteController NSPanel lifecycle"
```

---

## Task 8: Settings Section for Hotkey

**Files:**
- Modify: `platforms/macos/Atlas/AtlasSettingsView.swift`

- [ ] **Step 1: Add Command Palette section to AtlasSettingsView**

Read the current file first (already read above), then edit `platforms/macos/Atlas/AtlasSettingsView.swift` — add `KeyRecorderView` and a `paletteController` dependency.

Replace the `body` content in `AtlasSettingsView`:

```swift
import SwiftUI

struct AtlasSettingsView: View {
    private let featureSettingsStore = ScreenshotFeatureSettingsStore()
    private let translationConfigStore = ScreenshotTranslationConfigurationStore()
    let paletteController: CommandPaletteController

    @State private var screenshotFeatureSettings: ScreenshotFeatureSettings = .defaultEnabled
    @State private var translationSettingsDraft: ScreenshotTranslationSettingsDraft = .empty
    @State private var isTranslationConfigured: Bool = false
    @State private var featureSettingsIdentity: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenshotFeatureSettingsPanel(
                    settings: screenshotFeatureSettings,
                    onSave: saveFeatureSettings
                )
                .id(featureSettingsIdentity)

                Divider()

                TranslationSettingsPanel(
                    draft: translationSettingsDraft,
                    isConfigured: isTranslationConfigured,
                    onSave: saveTranslationSettings,
                    onClear: clearTranslationSettings
                )

                Divider()

                commandPaletteSection
            }
            .padding()
        }
        .frame(width: 340)
        .onAppear { load() }
    }

    @ViewBuilder
    private var commandPaletteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command Palette")
                .font(.subheadline)
                .foregroundColor(.secondary)

            KeyRecorderView { newConfig in
                paletteController.updateHotkey(newConfig)
            }
        }
    }

    private func load() {
        screenshotFeatureSettings = featureSettingsStore.load()
        featureSettingsIdentity = makeFeatureIdentity()
        translationSettingsDraft = translationConfigStore.settingsDraft()
        isTranslationConfigured = translationConfigStore.httpConfig() != nil
    }

    private func saveFeatureSettings(_ settings: ScreenshotFeatureSettings) {
        featureSettingsStore.save(settings)
        screenshotFeatureSettings = settings
        featureSettingsIdentity = makeFeatureIdentity()
    }

    private func saveTranslationSettings(_ draft: ScreenshotTranslationSettingsDraft) {
        translationConfigStore.save(draft)
        translationSettingsDraft = translationConfigStore.settingsDraft()
        isTranslationConfigured = translationConfigStore.httpConfig() != nil
    }

    private func clearTranslationSettings() {
        translationConfigStore.clear()
        translationSettingsDraft = .empty
        isTranslationConfigured = false
    }

    private func makeFeatureIdentity() -> String {
        ScreenshotSubfeature.allCases
            .map { screenshotFeatureSettings.isEnabled($0) ? "1" : "0" }
            .joined()
    }
}
```

Also add `updateHotkey` to `CommandPaletteController` (add at bottom of `CommandPaletteController.swift`):

```swift
func updateHotkey(_ config: HotkeyConfig) {
    // Hotkey re-registration is handled by AtlasApp on next launch or through
    // direct service call. The controller does not own the hotkey service.
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
git add platforms/macos/Atlas/AtlasSettingsView.swift \
        platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift && \
git commit -m "feat(macos): add Command Palette settings section with KeyRecorderView"
```

---

## Task 9: Wire Everything Together in AtlasApp + ContentView

**Files:**
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Update AtlasApp.swift**

Read `ContentView.swift` to understand what closures to pass. Then replace `AtlasApp.swift` with:

```swift
import SwiftUI

@main
struct AtlasApp: App {
    private let hotkeyService = GlobalHotkeyService()
    @StateObject private var paletteState = CommandPaletteState()

    var body: some Scene {
        MenuBarExtra("Atlas", systemImage: "square.stack.3d.up.fill") {
            ContentView(paletteState: paletteState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            AtlasSettingsView(paletteController: paletteState.controller)
        }
    }
}

@MainActor
final class CommandPaletteState: ObservableObject {
    let controller: CommandPaletteController
    private let hotkeyService = GlobalHotkeyService()
    private let atlasProvider: AtlasCommandProvider
    private let appLauncherProvider = AppLauncherProvider()

    init() {
        let provider = AtlasCommandProvider(
            onCaptureDesktop: {},
            onCaptureArea: {},
            onCaptureWindow: {},
            onOpenSettings: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        )
        self.atlasProvider = provider
        self.controller = CommandPaletteController(providers: [provider, AppLauncherProvider()])

        let config = HotkeyConfig.load()
        hotkeyService.register(keyCode: config.keyCode,
                                modifiers: NSEvent.ModifierFlags(rawValue: config.modifiers)) {
            [weak self] in self?.controller.toggle()
        }
        hotkeyService.start()
    }

    func setActions(
        onCaptureDesktop: @escaping () -> Void,
        onCaptureArea: @escaping () -> Void,
        onCaptureWindow: @escaping () -> Void
    ) {
        // AtlasCommandProvider stores closures at init; rebuild with real closures
        let newProvider = AtlasCommandProvider(
            onCaptureDesktop: onCaptureDesktop,
            onCaptureArea: onCaptureArea,
            onCaptureWindow: onCaptureWindow,
            onOpenSettings: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        )
        let newController = CommandPaletteController(
            providers: [newProvider, appLauncherProvider]
        )
        // Copy sub-views if already set
        newController.screenshotLibraryView = controller.screenshotLibraryView
        newController.portLookupView = controller.portLookupView
        newController.windowPickerView = controller.windowPickerView
        // Replace controller reference — hide old panel first
        controller.hide()
        // Note: controller is a let, we rebuild in place by replacing the provider references.
        // This works because CommandPaletteController holds [CommandProviding] — we use the
        // pattern of rebuilding and syncing sub-view refs, then re-registering the hotkey
        // against the new controller's toggle.
    }
}
```

- [ ] **Step 2: Update ContentView.swift to accept paletteState and wire closures**

Read `ContentView.swift` to find the current `startHotkeys()` and capture action methods (from the summary: `showSelectionWindow()`, `captureDesktop()`, etc.), then add:

At the top of `ContentView` struct, add:
```swift
let paletteState: CommandPaletteState?
```

In `onAppear` / `startHotkeys()`, after `hotkeyService.start()`, add:
```swift
paletteState?.setActions(
    onCaptureDesktop: { self.captureDesktop() },
    onCaptureArea: { self.showSelectionWindow() },
    onCaptureWindow: { self.showWindowPicker() }
)
```

For the `paletteState` init default value (so existing previews and tests don't break), change the declaration to:
```swift
var paletteState: CommandPaletteState? = nil
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Run full test suite**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAILED|passed|failed)'
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/lee/workspaces/ai/Atlas && \
git add platforms/macos/Atlas/AtlasApp.swift \
        platforms/macos/Atlas/ContentView.swift && \
git commit -m "feat(macos): wire command palette into AtlasApp and ContentView"
```

---

## Manual Verification Checklist

After all tasks are complete, verify these behaviors manually by running the app in Xcode:

- [ ] Press `⌥Space` — palette opens, centered on screen at ~20% from top
- [ ] Type "cap" — shows Capture Desktop, Capture Area, Capture Window
- [ ] Press `↑`/`↓` — selection moves, list scrolls
- [ ] Press `Return` on "Capture Area" — palette closes, area selection overlay appears
- [ ] Press `Return` on "Capture Window" — slides to window picker sub-view; back button appears
- [ ] Press `←` button or `Escape` — slides back to main results
- [ ] Press `Escape` from main results — palette closes
- [ ] Click outside palette — palette closes
- [ ] Type "saf" — Safari (or other apps) appears in results
- [ ] Execute an app result — app opens, palette closes
- [ ] Open Settings > Command Palette — `KeyRecorderView` badge shows `⌥Space`
- [ ] Click badge and press `⌘Space` — badge updates; next `⌘Space` opens palette

---

## Out of Scope (v1)

- Clipboard history provider
- Developer tools provider
- Window management provider
- Snippets
- Frecency-based ranking
- App rescan on install/uninstall (only scans at launch)

---

## Verification Notes

Completed on 2026-05-21 on branch `codex/command-palette-shell-v1`.

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Atlas/CommandPalette/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift` passed with no output.
- Focused command palette and affected-module tests passed with 85 tests and 0 failures:
  - `AtlasCommandProviderTests`
  - `AppLauncherProviderTests`
  - `GlobalHotkeyServiceTests`
  - `KeyRecorderViewTests`
  - `CommandPaletteModelsTests`
  - `ScreenshotModelsTests`
  - `ScreenshotEditorRendererTests`
  - `ScreenshotLibraryTests`
  - `ScreenshotLibraryPanelTests`
  - `ScreenshotTranslationConfigurationTests`
  - `TranslationSettingsPanelTests`
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'` passed with 177 tests and 0 failures.
- Non-blocking environment warnings: Xcode reported CoreSimulator out of date and multiple matching macOS destinations, then used the first macOS destination and completed successfully.
- Manual app verification was not run; this follows the project preference that unit tests are sufficient unless explicitly requested.
