# Command Palette App Rescan v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh command palette app-launcher results when application directories change, without restarting Atlas.

**Architecture:** Split app discovery out of `AppLauncherProvider` into an injectable scanner and add an injectable application-change observer. The provider owns a cached app list, refreshes that cache at init, and refreshes again when the observer reports application directory changes. Tests use fake scanners/observers so no real filesystem watcher or `/Applications` contents are required.

**Tech Stack:** Swift, AppKit `NSWorkspace`, Foundation `FileManager`, `DispatchSourceFileSystemObject`, XCTest, Xcode project updates via `xcodeproj`.

---

## Scope

This plan implements App Launcher refresh v1:

- Extract application scanning into `ApplicationScanning`.
- Add a default `FileSystemApplicationScanner` that scans the existing app directories.
- Add an `ApplicationChangeObserving` abstraction.
- Add a default `ApplicationDirectoryChangeObserver` that watches app directories and calls back when they change.
- Update `AppLauncherProvider` to refresh its cached app list at init and when the observer fires.
- Keep existing app search behavior and result cap unchanged.

Out of scope:

- Global result reordering.
- UI refresh indicators.
- Deep recursive scanning of app bundles.
- Watching arbitrary user-configured directories.
- App metadata indexing beyond app name and URL.
- Manual app-management UI.

## File Map

**New files:**

- `platforms/macos/Atlas/CommandPalette/ApplicationScanner.swift`
  - Defines `ApplicationScanning`.
  - Implements `FileSystemApplicationScanner`.
  - Owns application directory list and deduplication.

- `platforms/macos/Atlas/CommandPalette/ApplicationChangeObserver.swift`
  - Defines `ApplicationChangeObserving`.
  - Implements `ApplicationDirectoryChangeObserver`.
  - Watches application directories and calls a callback after file-system changes.

- `platforms/macos/AtlasTests/ApplicationScannerTests.swift`
  - Tests scanner directory filtering, `.app` filtering, deduplication, sorting, and inaccessible directories.

- `platforms/macos/AtlasTests/AppLauncherRefreshTests.swift`
  - Tests provider initial scan and refresh-on-change behavior with fakes.

**Modified files:**

- `platforms/macos/Atlas/CommandPalette/AppLauncherProvider.swift`
  - Removes embedded scanning responsibility.
  - Accepts scanner and observer dependencies.
  - Adds `refreshApplications()`.
  - Keeps search/scoring/result mapping behavior.

- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new source and test files to targets.

---

## Task 1: Application Scanner

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/ApplicationScanner.swift`
- Create: `platforms/macos/AtlasTests/ApplicationScannerTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing scanner tests**

Create `platforms/macos/AtlasTests/ApplicationScannerTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ApplicationScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApplicationScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
        try super.tearDownWithError()
    }

    func testScannerReturnsOnlyAppBundles() throws {
        let appURL = try makeDirectory("Safari.app")
        _ = try makeDirectory("NotAnApp")
        try "text".write(to: root.appendingPathComponent("Notes.txt"), atomically: true, encoding: .utf8)

        let scanner = FileSystemApplicationScanner(directories: [root])

        XCTAssertEqual(scanner.scanApplications(), [
            AppEntry(name: "Safari", url: appURL),
        ])
    }

    func testScannerDeduplicatesByURL() throws {
        let appURL = try makeDirectory("Xcode.app")
        let scanner = FileSystemApplicationScanner(directories: [root, root])

        XCTAssertEqual(scanner.scanApplications(), [
            AppEntry(name: "Xcode", url: appURL),
        ])
    }

    func testScannerSortsByName() throws {
        let zedURL = try makeDirectory("Zed.app")
        let arcURL = try makeDirectory("Arc.app")
        let xcodeURL = try makeDirectory("Xcode.app")

        let scanner = FileSystemApplicationScanner(directories: [root])

        XCTAssertEqual(scanner.scanApplications(), [
            AppEntry(name: "Arc", url: arcURL),
            AppEntry(name: "Xcode", url: xcodeURL),
            AppEntry(name: "Zed", url: zedURL),
        ])
    }

    func testScannerSkipsUnreadableOrMissingDirectories() throws {
        let existingURL = try makeDirectory("Terminal.app")
        let missing = root.appendingPathComponent("Missing", isDirectory: true)
        let scanner = FileSystemApplicationScanner(directories: [missing, root])

        XCTAssertEqual(scanner.scanApplications(), [
            AppEntry(name: "Terminal", url: existingURL),
        ])
    }

    func testDefaultDirectoriesIncludeUserApplications() {
        let userApplications = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Applications"))

        XCTAssertTrue(FileSystemApplicationScanner.defaultDirectories.contains(userApplications))
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 2: Add test file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
unless group.files.any? { |f| f.path == 'ApplicationScannerTests.swift' }
  ref = group.new_file('ApplicationScannerTests.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 3: Run scanner tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/ApplicationScannerTests
```

Expected: compile failure mentioning missing `FileSystemApplicationScanner`.

- [ ] **Step 4: Write the scanner implementation**

Create `platforms/macos/Atlas/CommandPalette/ApplicationScanner.swift`:

```swift
import Foundation

protocol ApplicationScanning {
    func scanApplications() -> [AppEntry]
}

struct FileSystemApplicationScanner: ApplicationScanning {
    static let defaultDirectories = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/Applications/Utilities"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Applications")),
    ]

    private let directories: [URL]
    private let fileManager: FileManager

    init(
        directories: [URL] = Self.defaultDirectories,
        fileManager: FileManager = .default
    ) {
        self.directories = directories
        self.fileManager = fileManager
    }

    func scanApplications() -> [AppEntry] {
        var entries: [AppEntry] = []

        for directory in directories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            for url in contents where url.pathExtension == "app" {
                entries.append(AppEntry(
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url
                ))
            }
        }

        var seen = Set<URL>()
        var uniqueEntries: [AppEntry] = []
        for entry in entries where !seen.contains(entry.url) {
            seen.insert(entry.url)
            uniqueEntries.append(entry)
        }

        return uniqueEntries.sorted { $0.name < $1.name }
    }
}
```

- [ ] **Step 5: Add source file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']['CommandPalette']
unless group.files.any? { |f| f.path == 'ApplicationScanner.swift' }
  ref = group.new_file('ApplicationScanner.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 6: Run scanner tests to verify they pass**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/ApplicationScannerTests
```

Expected: `ApplicationScannerTests` passes with 5 tests and 0 failures.

- [ ] **Step 7: Commit**

Run:

```bash
git add platforms/macos/Atlas/CommandPalette/ApplicationScanner.swift \
        platforms/macos/AtlasTests/ApplicationScannerTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add application scanner"
```

---

## Task 2: Application Change Observer

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/ApplicationChangeObserver.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the observer implementation**

Create `platforms/macos/Atlas/CommandPalette/ApplicationChangeObserver.swift`:

```swift
import Foundation

protocol ApplicationChangeObserving: AnyObject {
    func setChangeHandler(_ handler: @escaping () -> Void)
    func start()
    func stop()
}

final class ApplicationDirectoryChangeObserver: ApplicationChangeObserving {
    private let directories: [URL]
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private var handler: (() -> Void)?

    init(directories: [URL] = FileSystemApplicationScanner.defaultDirectories) {
        self.directories = directories
    }

    deinit {
        stop()
    }

    func setChangeHandler(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() {
        stop()

        for directory in directories {
            let fileDescriptor = open(directory.path, O_EVTONLY)
            guard fileDescriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .delete, .rename],
                queue: DispatchQueue.global(qos: .utility)
            )

            source.setEventHandler { [weak self] in
                self?.handler?()
            }
            source.setCancelHandler {
                close(fileDescriptor)
            }

            fileDescriptors.append(fileDescriptor)
            sources.append(source)
            source.resume()
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        fileDescriptors.removeAll()
    }
}
```

- [ ] **Step 2: Add source file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']['CommandPalette']
unless group.files.any? { |f| f.path == 'ApplicationChangeObserver.swift' }
  ref = group.new_file('ApplicationChangeObserver.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 3: Build to verify observer compiles**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

Run:

```bash
git add platforms/macos/Atlas/CommandPalette/ApplicationChangeObserver.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add application change observer"
```

---

## Task 3: Provider Refresh Integration

**Files:**
- Modify: `platforms/macos/Atlas/CommandPalette/AppLauncherProvider.swift`
- Create: `platforms/macos/AtlasTests/AppLauncherRefreshTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing refresh tests**

Create `platforms/macos/AtlasTests/AppLauncherRefreshTests.swift`:

```swift
import XCTest
@testable import Atlas

final class AppLauncherRefreshTests: XCTestCase {
    func testProviderScansOnInitWhenScannerIsInjected() {
        let scanner = FakeApplicationScanner(scans: [
            [AppEntry(name: "Initial", url: url("Initial"))],
        ])
        let observer = FakeApplicationChangeObserver()

        let provider = AppLauncherProvider(scanner: scanner, changeObserver: observer)

        XCTAssertEqual(scanner.scanCount, 1)
        XCTAssertEqual(provider.results(for: "initial").map(\.title), ["Initial"])
    }

    func testRefreshApplicationsReplacesCachedApps() {
        let scanner = FakeApplicationScanner(scans: [
            [AppEntry(name: "Initial", url: url("Initial"))],
            [AppEntry(name: "Updated", url: url("Updated"))],
        ])
        let provider = AppLauncherProvider(scanner: scanner, changeObserver: FakeApplicationChangeObserver())

        provider.refreshApplications()

        XCTAssertTrue(provider.results(for: "initial").isEmpty)
        XCTAssertEqual(provider.results(for: "updated").map(\.title), ["Updated"])
    }

    func testChangeObserverTriggersRefresh() {
        let scanner = FakeApplicationScanner(scans: [
            [AppEntry(name: "Initial", url: url("Initial"))],
            [AppEntry(name: "Installed", url: url("Installed"))],
        ])
        let observer = FakeApplicationChangeObserver()
        let provider = AppLauncherProvider(scanner: scanner, changeObserver: observer)

        observer.triggerChange()

        XCTAssertEqual(scanner.scanCount, 2)
        XCTAssertEqual(provider.results(for: "installed").map(\.title), ["Installed"])
    }

    func testInjectedStaticAppsDoNotStartObserver() {
        let observer = FakeApplicationChangeObserver()
        let provider = AppLauncherProvider(
            apps: [AppEntry(name: "Static", url: url("Static"))],
            changeObserver: observer
        )

        XCTAssertFalse(observer.didStart)
        XCTAssertEqual(provider.results(for: "static").map(\.title), ["Static"])
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Applications/\(name).app")
    }
}

private final class FakeApplicationScanner: ApplicationScanning {
    private let scans: [[AppEntry]]
    private(set) var scanCount = 0

    init(scans: [[AppEntry]]) {
        self.scans = scans
    }

    func scanApplications() -> [AppEntry] {
        let index = min(scanCount, scans.count - 1)
        scanCount += 1
        return scans[index]
    }
}

private final class FakeApplicationChangeObserver: ApplicationChangeObserving {
    private var handler: (() -> Void)?
    private(set) var didStart = false
    private(set) var didStop = false

    func setChangeHandler(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() {
        didStart = true
    }

    func stop() {
        didStop = true
    }

    func triggerChange() {
        handler?()
    }
}
```

- [ ] **Step 2: Add test file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
unless group.files.any? { |f| f.path == 'AppLauncherRefreshTests.swift' }
  ref = group.new_file('AppLauncherRefreshTests.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [ ] **Step 3: Run refresh tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/AppLauncherRefreshTests
```

Expected: compile failure because `AppLauncherProvider(scanner:changeObserver:)` and `refreshApplications()` do not exist yet.

- [ ] **Step 4: Refactor `AppLauncherProvider`**

Replace `platforms/macos/Atlas/CommandPalette/AppLauncherProvider.swift` with:

```swift
import AppKit
import Foundation

struct AppEntry: Equatable, Sendable {
    let name: String
    let url: URL
}

final class AppLauncherProvider: CommandProviding, @unchecked Sendable {
    private static let exactPrefixBaseScore = 1000
    private static let maxPrefixLengthBonus = 100
    private static let containsMatchScore = 500
    private static let fuzzyMatchBaseScore = 100
    private static let consecutiveMatchBonus = 10
    private static let maxResultsCount = 5

    private let lock = NSLock()
    private let scanner: ApplicationScanning?
    private let changeObserver: ApplicationChangeObserving?
    private var _apps: [AppEntry] = []

    private var apps: [AppEntry] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _apps
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _apps = newValue
        }
    }

    init(
        apps: [AppEntry]? = nil,
        scanner: ApplicationScanning = FileSystemApplicationScanner(),
        changeObserver: ApplicationChangeObserving? = ApplicationDirectoryChangeObserver()
    ) {
        if let apps {
            self._apps = apps
            self.scanner = nil
            self.changeObserver = nil
        } else {
            self.scanner = scanner
            self.changeObserver = changeObserver
            refreshApplications()
            changeObserver?.setChangeHandler { [weak self] in
                self?.refreshApplications()
            }
            changeObserver?.start()
        }
    }

    deinit {
        changeObserver?.stop()
    }

    func refreshApplications() {
        guard let scanner else { return }
        apps = scanner.scanApplications()
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
            .prefix(Self.maxResultsCount)
            .map { entry, _ in
                PaletteCommand(
                    id: UUID(),
                    title: entry.name,
                    subtitle: nil,
                    icon: .appIcon(entry.url),
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

        if t.hasPrefix(q) { return exactPrefixBaseScore + (maxPrefixLengthBonus - t.count) }
        if t.contains(q) { return containsMatchScore }

        let qChars = Array(q)
        let tChars = Array(t)

        var qi = 0
        var consecutiveBonus = 0
        var lastMatchIndex: Int? = nil

        for ti in 0..<tChars.count {
            if tChars[ti] == qChars[qi] {
                if let last = lastMatchIndex, last + 1 == ti {
                    consecutiveBonus += consecutiveMatchBonus
                }
                lastMatchIndex = ti
                qi += 1
                if qi == qChars.count {
                    break
                }
            }
        }

        guard qi == qChars.count else { return 0 }
        return fuzzyMatchBaseScore + consecutiveBonus
    }
}
```

- [ ] **Step 5: Run focused app launcher tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/AppLauncherProviderTests \
  -only-testing:AtlasTests/ApplicationScannerTests \
  -only-testing:AtlasTests/AppLauncherRefreshTests
```

Expected: selected app launcher tests pass with 18 tests and 0 failures.

- [ ] **Step 6: Commit**

Run:

```bash
git add platforms/macos/Atlas/CommandPalette/AppLauncherProvider.swift \
        platforms/macos/AtlasTests/AppLauncherRefreshTests.swift \
        platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): refresh app launcher results on app changes"
```

---

## Task 4: Verify and Record

**Files:**
- Modify: `docs/superpowers/plans/2026-05-22-command-palette-app-rescan-v1.md`

- [ ] **Step 1: Run focused command palette tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/AppLauncherProviderTests \
  -only-testing:AtlasTests/ApplicationScannerTests \
  -only-testing:AtlasTests/AppLauncherRefreshTests \
  -only-testing:AtlasTests/CommandPaletteRankerTests \
  -only-testing:AtlasTests/CommandUsageStoreTests
```

Expected: selected tests pass with 28 tests and 0 failures.

- [ ] **Step 2: Run full macOS test suite**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS'
```

Expected: full suite passes. Existing CoreSimulator/linkd warnings are non-blocking if the test run ends with `** TEST SUCCEEDED **`.

- [ ] **Step 3: Append verification notes**

Append this section to `docs/superpowers/plans/2026-05-22-command-palette-app-rescan-v1.md`:

```markdown
## Verification Notes

Completed on 2026-05-22 on branch `codex/command-palette-app-rescan-v1`.

- Focused tests:
  - `AppLauncherProviderTests`
  - `ApplicationScannerTests`
  - `AppLauncherRefreshTests`
  - `CommandPaletteRankerTests`
  - `CommandUsageStoreTests`
- Full macOS test suite:
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Manual install/uninstall verification was not run; this follows the project preference that unit tests are sufficient unless explicitly requested.
```

- [ ] **Step 4: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-command-palette-app-rescan-v1.md
git commit -m "docs: record command palette app rescan verification"
```

---

## Self-Review

1. **Spec coverage:** This plan extracts app scanning, adds an app-directory observer, refreshes `AppLauncherProvider` on changes, preserves existing search behavior, and verifies both scanning and refresh behavior with deterministic tests.

2. **Placeholder scan:** The plan contains concrete file paths, exact test code, implementation code, commands, expected results, and commit messages. It does not use placeholder steps.

3. **Type consistency:** `ApplicationScanning`, `FileSystemApplicationScanner`, `ApplicationChangeObserving`, and `ApplicationDirectoryChangeObserver` are defined before `AppLauncherProvider` references them. Refresh tests use the same protocols introduced in prior tasks.
