# Clipboard History v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current in-memory clipboard command provider with gated, persistent clipboard history for text plus image metadata.

**Architecture:** Keep clipboard capture in Swift because it depends on `NSPasteboard`, and keep the Rust/UniFFI layer limited to registering the `clipboard` feature flag. `CommandPaletteState` owns one shared `ClipboardHistoryStore`, injects it into `ClipboardHistoryProvider`, and exposes the same store to `ContentView` so command palette capture and panel rendering read the same history. `ClipboardHistoryProvider` captures through an injected `ClipboardReading` interface, maps searchable history to command palette results, and calls `onHistoryChanged` after capture so the visible panel snapshot reloads without restarting the app. `ClipboardHistoryPanel` provides privacy messaging, search, delete, and clear-all controls in the main Atlas window behind Feature Center gating.

**Tech Stack:** Swift, SwiftUI, AppKit `NSPasteboard`, Foundation `UserDefaults`, XCTest, Rust feature registry, UniFFI feature list, explicit Xcode PBX project membership via `xcodeproj`.

---

## Scope

This plan implements:

- Persistent local clipboard history for text items.
- Image metadata entries without storing image bytes.
- Search across text and image metadata.
- Delete one item and clear all items.
- Max retention trimming.
- Feature Center gating so disabled clipboard history does not read the pasteboard or show UI.
- Privacy messaging in the Clipboard History panel.
- Tests using an injected clipboard reader so tests never touch the real pasteboard.

Out of scope:

- Persisting image data or thumbnails.
- Rich text/RTF history.
- iCloud sync.
- Keyboard shortcuts for individual clipboard entries.
- Exposing clipboard history through Rust or UniFFI beyond the `clipboard` feature flag.

## Current Baseline

`platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift` currently:

- Defines `ClipboardHistoryItem` with `id`, `text`, and `capturedAt`.
- Defines `ClipboardReading` with `changeCount`, `string()`, and `setString(_:)`.
- Captures current text from `NSPasteboard.general`.
- Stores entries only in provider memory.
- Returns command palette results for non-empty queries.
- Caps in-memory history with `maxHistoryCount`.

Preserve the injected-reader testing approach and extend it for image metadata.

## File Map

**New files:**

- `platforms/macos/Atlas/ClipboardHistoryStore.swift`
  - Defines `ClipboardHistoryItem`, `ClipboardHistoryContent`, `ClipboardImageMetadata`, `ClipboardHistoryStoring`, and `ClipboardHistoryStore`.
  - Persists text entries and image metadata to `UserDefaults`.
  - Applies max retention on save/capture.

- `platforms/macos/Atlas/ClipboardHistoryPanel.swift`
  - SwiftUI panel with privacy copy, search, item list, delete, clear-all, and copy-text actions.

- `platforms/macos/AtlasTests/ClipboardHistoryStoreTests.swift`
  - Tests persistence, search, image metadata, delete, clear-all, duplicate text handling, and retention.

**Modified files:**

- `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift`
  - Reuses store-backed `ClipboardHistoryItem`.
  - Extends `ClipboardReading` with `imageMetadata()`.
  - Captures text or image metadata into `ClipboardHistoryStoring`.
  - Calls `onHistoryChanged` after successful capture so the panel can reload.
  - Returns no results and performs no capture when the `clipboard` feature is disabled.

- `platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift`
  - Updates fake reader and tests for store-backed capture, image metadata, disabled gating, search, copy, and the panel reload callback.

- `platforms/macos/AtlasTests/SnippetsProviderTests.swift`
  - Updates `FakeSnippetClipboard` with `imageMetadata() -> nil` because it also conforms to `ClipboardReading`.

- `crates/atlas-core/src/features.rs`
  - Registers the `clipboard` feature with default disabled status.
  - Updates sorted feature test expectation.

- `platforms/macos/Atlas/AtlasModule.swift`
  - Adds `case clipboard` and the visible title `Clipboard History`.

- `platforms/macos/Atlas/FeatureModels.swift`
  - Maps `AtlasModule.clipboard.featureName` to the `Clipboard History` title.

- `platforms/macos/Atlas/ContentView.swift`
  - Reads the shared `ClipboardHistoryStore` from `CommandPaletteState`.
  - Shows `ClipboardHistoryPanel` only when the `clipboard` feature is enabled.
  - Updates the command palette clipboard provider when Feature Center toggles clipboard.

- `platforms/macos/Atlas/AtlasApp.swift`
  - Keeps a strong reference to the shared `ClipboardHistoryStore` and `ClipboardHistoryProvider`.
  - Adds `setClipboardHistoryEnabled(_:)` on `CommandPaletteState`.

- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new Swift app files to the `Atlas` target sources.
  - Adds new Swift test files to the `AtlasTests` target sources.

---

### Task 1: Register Clipboard Feature

**Files:**
- Modify: `crates/atlas-core/src/features.rs`
- Modify: `platforms/macos/Atlas/AtlasModule.swift`
- Modify: `platforms/macos/Atlas/FeatureModels.swift`
- Test: `crates/atlas-core/src/features.rs`
- Test: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

- [x] **Step 1: Update Rust feature registration**

In `crates/atlas-core/src/features.rs`, update `FeatureManager::new()`:

```rust
pub fn new() -> Self {
    let mut features = HashMap::new();
    features.insert("clipboard".to_string(), FeatureStatus::Disabled);
    features.insert("monitoring".to_string(), FeatureStatus::Disabled);
    features.insert("screenshot".to_string(), FeatureStatus::Disabled);
    features.insert("window-manager".to_string(), FeatureStatus::Disabled);
    Self { features }
}
```

In the same file, update `test_list_features_is_sorted_by_name`:

```rust
#[test]
fn test_list_features_is_sorted_by_name() {
    let fm = FeatureManager::new();
    let names: Vec<_> = fm.list_features().into_iter().map(|(name, _)| name).collect();

    assert_eq!(names, ["clipboard", "monitoring", "screenshot", "window-manager"]);
}
```

- [x] **Step 2: Update Swift module names**

Replace `platforms/macos/Atlas/AtlasModule.swift` with:

```swift
enum AtlasModule: String, CaseIterable, Identifiable {
    case clipboard
    case screenshot
    case monitoring

    var id: String { rawValue }

    var featureName: String {
        rawValue
    }

    var title: String {
        switch self {
        case .clipboard:
            return "Clipboard History"
        case .screenshot:
            return "Screenshot"
        case .monitoring:
            return "Monitoring"
        }
    }
}
```

- [x] **Step 3: Update FeatureModels title mapping**

In `platforms/macos/Atlas/FeatureModels.swift`, update `AtlasFeatureTitles.title(for:)`:

```swift
private enum AtlasFeatureTitles {
    static func title(for name: String) -> String {
        switch name {
        case AtlasModule.clipboard.featureName:
            return AtlasModule.clipboard.title
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

- [x] **Step 4: Extend FeatureModelsTests**

Add this test to `platforms/macos/AtlasTests/FeatureModelsTests.swift`:

```swift
func testClipboardFeatureUsesProductTitle() {
    let feature = AtlasFeature(name: "clipboard", isEnabled: false)

    XCTAssertEqual(feature.title, "Clipboard History")
}
```

- [x] **Step 5: Verify feature registration**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/FeatureModelsTests
```

Expected: Both commands pass. The Rust sorted-name assertion includes `clipboard`, and Swift feature title tests pass.

- [x] **Step 6: Commit feature registration**

Run:

```bash
git add crates/atlas-core/src/features.rs \
  platforms/macos/Atlas/AtlasModule.swift \
  platforms/macos/Atlas/FeatureModels.swift \
  platforms/macos/AtlasTests/FeatureModelsTests.swift
git commit -m "feat: register clipboard feature"
```

Expected: The commit contains only feature registration and title mapping changes.

---

### Task 2: Persistent Clipboard History Store

**Files:**
- Create: `platforms/macos/Atlas/ClipboardHistoryStore.swift`
- Create: `platforms/macos/AtlasTests/ClipboardHistoryStoreTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Create store tests**

Create `platforms/macos/AtlasTests/ClipboardHistoryStoreTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ClipboardHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ClipboardHistoryStoreTests"

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

    func testStartsEmpty() {
        let store = ClipboardHistoryStore(defaults: defaults)

        XCTAssertTrue(store.items().isEmpty)
    }

    func testAddTextPersistsNewestFirst() {
        let store = ClipboardHistoryStore(defaults: defaults)
        let first = Date(timeIntervalSince1970: 10)
        let second = Date(timeIntervalSince1970: 20)

        store.addText("alpha", capturedAt: first)
        store.addText("beta", capturedAt: second)

        let reloaded = ClipboardHistoryStore(defaults: defaults)
        XCTAssertEqual(reloaded.items().map(\.displayTitle), ["beta", "alpha"])
    }

    func testAddTextIgnoresBlankValues() {
        let store = ClipboardHistoryStore(defaults: defaults)

        store.addText(" \n ", capturedAt: Date(timeIntervalSince1970: 10))

        XCTAssertTrue(store.items().isEmpty)
    }

    func testAddTextMovesDuplicateToFront() {
        let store = ClipboardHistoryStore(defaults: defaults)

        store.addText("same", capturedAt: Date(timeIntervalSince1970: 10))
        store.addText("other", capturedAt: Date(timeIntervalSince1970: 20))
        store.addText("same", capturedAt: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(store.items().map(\.displayTitle), ["same", "other"])
        XCTAssertEqual(store.items().first?.capturedAt, Date(timeIntervalSince1970: 30))
    }

    func testAddImageMetadataPersistsWithoutImageBytes() {
        let store = ClipboardHistoryStore(defaults: defaults)
        let metadata = ClipboardImageMetadata(
            typeIdentifier: "public.png",
            pixelWidth: 640,
            pixelHeight: 480,
            byteCount: 2048
        )

        store.addImageMetadata(metadata, capturedAt: Date(timeIntervalSince1970: 40))

        XCTAssertEqual(store.items(), [
            ClipboardHistoryItem(
                id: store.items()[0].id,
                content: .image(metadata),
                capturedAt: Date(timeIntervalSince1970: 40)
            ),
        ])
        XCTAssertEqual(store.items().first?.displayTitle, "Image 640 x 480")
        XCTAssertEqual(store.items().first?.searchableText, "image public.png 640 x 480 2048 bytes")
    }

    func testSearchMatchesTextAndImageMetadata() {
        let store = ClipboardHistoryStore(defaults: defaults)
        store.addText("Invoice 42", capturedAt: Date(timeIntervalSince1970: 10))
        store.addImageMetadata(
            ClipboardImageMetadata(typeIdentifier: "public.tiff", pixelWidth: 100, pixelHeight: 200, byteCount: nil),
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(store.search("invoice").map(\.displayTitle), ["Invoice 42"])
        XCTAssertEqual(store.search("tiff").map(\.displayTitle), ["Image 100 x 200"])
    }

    func testDeleteRemovesMatchingItem() {
        let store = ClipboardHistoryStore(defaults: defaults)
        store.addText("keep", capturedAt: Date(timeIntervalSince1970: 10))
        store.addText("remove", capturedAt: Date(timeIntervalSince1970: 20))
        let removedID = store.items()[0].id

        store.delete(id: removedID)

        XCTAssertEqual(store.items().map(\.displayTitle), ["keep"])
    }

    func testClearRemovesAllItems() {
        let store = ClipboardHistoryStore(defaults: defaults)
        store.addText("one", capturedAt: Date(timeIntervalSince1970: 10))
        store.addText("two", capturedAt: Date(timeIntervalSince1970: 20))

        store.clear()

        XCTAssertTrue(store.items().isEmpty)
    }

    func testMaxRetentionIsApplied() {
        let store = ClipboardHistoryStore(defaults: defaults, maxHistoryCount: 2)

        store.addText("one", capturedAt: Date(timeIntervalSince1970: 10))
        store.addText("two", capturedAt: Date(timeIntervalSince1970: 20))
        store.addText("three", capturedAt: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(store.items().map(\.displayTitle), ["three", "two"])
    }
}
```

- [x] **Step 2: Add the test file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'AtlasTests' }
group = proj.main_group['AtlasTests']
unless group.files.any? { |f| f.path == 'ClipboardHistoryStoreTests.swift' }
  ref = group.new_file('ClipboardHistoryStoreTests.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [x] **Step 3: Run store tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/ClipboardHistoryStoreTests
```

Expected: The build fails because `ClipboardHistoryStore`, `ClipboardHistoryItem`, and `ClipboardImageMetadata` do not exist yet.

- [x] **Step 4: Create the store implementation**

Create `platforms/macos/Atlas/ClipboardHistoryStore.swift`:

```swift
import Foundation

struct ClipboardImageMetadata: Codable, Equatable, Sendable {
    let typeIdentifier: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int?

    var displayTitle: String {
        "Image \(pixelWidth) x \(pixelHeight)"
    }

    var searchableText: String {
        var parts = ["image", typeIdentifier, "\(pixelWidth) x \(pixelHeight)"]
        if let byteCount {
            parts.append("\(byteCount) bytes")
        }
        return parts.joined(separator: " ")
    }
}

enum ClipboardHistoryContent: Codable, Equatable, Sendable {
    case text(String)
    case image(ClipboardImageMetadata)

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case image
    }

    private enum Kind: String, Codable {
        case text
        case image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(try container.decode(ClipboardImageMetadata.self, forKey: .image))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .image(let metadata):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(metadata, forKey: .image)
        }
    }
}

struct ClipboardHistoryItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let content: ClipboardHistoryContent
    let capturedAt: Date

    var displayTitle: String {
        switch content {
        case .text(let text):
            let firstLine = text
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? text
            return String(firstLine.prefix(80))
        case .image(let metadata):
            return metadata.displayTitle
        }
    }

    var searchableText: String {
        switch content {
        case .text(let text):
            return text
        case .image(let metadata):
            return metadata.searchableText
        }
    }

    var textValue: String? {
        if case .text(let text) = content {
            return text
        }
        return nil
    }
}

protocol ClipboardHistoryStoring: AnyObject {
    func items() -> [ClipboardHistoryItem]
    func search(_ query: String) -> [ClipboardHistoryItem]
    func addText(_ text: String, capturedAt: Date)
    func addImageMetadata(_ metadata: ClipboardImageMetadata, capturedAt: Date)
    func delete(id: UUID)
    func clear()
}

final class ClipboardHistoryStore: ClipboardHistoryStoring {
    private static let storageKey = "clipboardHistory.items"

    private let defaults: UserDefaults
    private let maxHistoryCount: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, maxHistoryCount: Int = 50) {
        self.defaults = defaults
        self.maxHistoryCount = maxHistoryCount
    }

    func items() -> [ClipboardHistoryItem] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? decoder.decode([ClipboardHistoryItem].self, from: data) else {
            return []
        }
        return Array(decoded.prefix(maxHistoryCount))
    }

    func search(_ query: String) -> [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items() }

        return items().filter {
            $0.searchableText.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func addText(_ text: String, capturedAt: Date) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item = ClipboardHistoryItem(id: UUID(), content: .text(text), capturedAt: capturedAt)
        save(inserted: item) { existing in
            existing.textValue == text
        }
    }

    func addImageMetadata(_ metadata: ClipboardImageMetadata, capturedAt: Date) {
        let item = ClipboardHistoryItem(id: UUID(), content: .image(metadata), capturedAt: capturedAt)
        save(inserted: item) { existing in
            existing.content == .image(metadata)
        }
    }

    func delete(id: UUID) {
        save(items().filter { $0.id != id })
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func save(inserted item: ClipboardHistoryItem, removing shouldRemove: (ClipboardHistoryItem) -> Bool) {
        let remaining = items().filter { !shouldRemove($0) }
        save([item] + remaining)
    }

    private func save(_ newItems: [ClipboardHistoryItem]) {
        let retained = Array(newItems.prefix(maxHistoryCount))
        if let data = try? encoder.encode(retained) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
```

- [x] **Step 5: Add the store file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']
unless group.files.any? { |f| f.path == 'ClipboardHistoryStore.swift' }
  ref = group.new_file('ClipboardHistoryStore.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [x] **Step 6: Verify store tests pass**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/ClipboardHistoryStoreTests
```

Expected: `ClipboardHistoryStoreTests` passes.

- [x] **Step 7: Commit store**

Run:

```bash
git add platforms/macos/Atlas/ClipboardHistoryStore.swift \
  platforms/macos/AtlasTests/ClipboardHistoryStoreTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: persist clipboard history"
```

Expected: The commit includes the store, store tests, and explicit PBX membership entries.

---

### Task 3: Store-Backed Command Palette Provider

**Files:**
- Modify: `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift`
- Modify: `platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift`
- Modify: `platforms/macos/AtlasTests/SnippetsProviderTests.swift`

- [x] **Step 1: Replace provider tests**

Replace `platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift` with:

```swift
import XCTest
@testable import Atlas

final class ClipboardHistoryProviderTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 100)

    func testCapturesCurrentClipboardTextIntoStore() {
        let reader = FakeClipboardReader(text: "hello")
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { true }, dateProvider: { self.now })

        provider.captureCurrentClipboard()

        XCTAssertEqual(store.items().map(\.textValue), ["hello"])
    }

    func testCapturesImageMetadataWhenNoTextExists() {
        let metadata = ClipboardImageMetadata(typeIdentifier: "public.png", pixelWidth: 320, pixelHeight: 240, byteCount: 1024)
        let reader = FakeClipboardReader(text: nil, imageMetadata: metadata)
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { true }, dateProvider: { self.now })

        provider.captureCurrentClipboard()

        XCTAssertEqual(store.items().map(\.content), [.image(metadata)])
    }

    func testDisabledFeatureDoesNotReadClipboardOrReturnResults() {
        let reader = FakeClipboardReader(text: "secret")
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { false })

        provider.captureCurrentClipboard()
        let results = provider.results(for: "clip")

        XCTAssertEqual(reader.stringReadCount, 0)
        XCTAssertTrue(store.items().isEmpty)
        XCTAssertTrue(results.isEmpty)
    }

    func testBlankQueryReturnsNoResults() {
        let reader = FakeClipboardReader(text: "hello")
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { true })

        provider.captureCurrentClipboard()

        XCTAssertTrue(provider.results(for: "").isEmpty)
    }

    func testClipboardQueryReturnsRecentTextResults() {
        let reader = FakeClipboardReader(text: "hello")
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { true })

        provider.captureCurrentClipboard()
        let results = provider.results(for: "clip")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "hello")
        XCTAssertEqual(results.first?.category, "Clipboard")
        XCTAssertEqual(results.first?.icon, .sfSymbol("doc.on.clipboard"))
    }

    func testQueryMatchesImageMetadata() {
        let metadata = ClipboardImageMetadata(typeIdentifier: "public.tiff", pixelWidth: 100, pixelHeight: 200, byteCount: nil)
        let reader = FakeClipboardReader(text: nil, imageMetadata: metadata)
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { true })

        provider.captureCurrentClipboard()
        let results = provider.results(for: "tiff")

        XCTAssertEqual(results.first?.title, "Image 100 x 200")
        XCTAssertEqual(results.first?.subtitle, "Image metadata only")
    }

    func testExecutingTextResultCopiesTextBackToClipboard() {
        let reader = FakeClipboardReader(text: "first")
        let store = InMemoryClipboardHistoryStore()
        let provider = ClipboardHistoryProvider(reader: reader, store: store, isEnabled: { true })

        provider.captureCurrentClipboard()
        reader.bumpChangeCount(text: "second", imageMetadata: nil)
        provider.captureCurrentClipboard()

        let result = provider.results(for: "first").first
        if case .execute(let execute)? = result?.action {
            execute()
        } else {
            XCTFail("expected executable clipboard result")
        }

        XCTAssertEqual(reader.writtenText, "first")
    }

    func testCaptureNotifiesPanelReloadCallback() {
        let reader = FakeClipboardReader(text: "visible without restart")
        let store = InMemoryClipboardHistoryStore()
        var panelItems: [ClipboardHistoryItem] = []
        let provider = ClipboardHistoryProvider(
            reader: reader,
            store: store,
            isEnabled: { true },
            onHistoryChanged: {
                panelItems = store.items()
            }
        )

        provider.captureCurrentClipboard()

        XCTAssertEqual(panelItems.map(\.textValue), ["visible without restart"])
    }
}

private final class FakeClipboardReader: ClipboardReading {
    private(set) var changeCount: Int
    private var currentText: String?
    private var currentImageMetadata: ClipboardImageMetadata?
    private(set) var writtenText: String?
    private(set) var stringReadCount = 0

    init(text: String?, imageMetadata: ClipboardImageMetadata? = nil, changeCount: Int = 1) {
        self.currentText = text
        self.currentImageMetadata = imageMetadata
        self.changeCount = changeCount
    }

    func string() -> String? {
        stringReadCount += 1
        return currentText
    }

    func imageMetadata() -> ClipboardImageMetadata? {
        currentImageMetadata
    }

    func setString(_ text: String) {
        writtenText = text
        currentText = text
        currentImageMetadata = nil
        changeCount += 1
    }

    func bumpChangeCount(text: String?, imageMetadata: ClipboardImageMetadata?) {
        currentText = text
        currentImageMetadata = imageMetadata
        changeCount += 1
    }
}

private final class InMemoryClipboardHistoryStore: ClipboardHistoryStoring {
    private var storedItems: [ClipboardHistoryItem] = []

    func items() -> [ClipboardHistoryItem] {
        storedItems
    }

    func search(_ query: String) -> [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return storedItems }
        return storedItems.filter { $0.searchableText.localizedCaseInsensitiveContains(trimmed) }
    }

    func addText(_ text: String, capturedAt: Date) {
        storedItems.insert(ClipboardHistoryItem(id: UUID(), content: .text(text), capturedAt: capturedAt), at: 0)
    }

    func addImageMetadata(_ metadata: ClipboardImageMetadata, capturedAt: Date) {
        storedItems.insert(ClipboardHistoryItem(id: UUID(), content: .image(metadata), capturedAt: capturedAt), at: 0)
    }

    func delete(id: UUID) {
        storedItems.removeAll { $0.id == id }
    }

    func clear() {
        storedItems = []
    }
}
```

- [x] **Step 2: Run provider tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/ClipboardHistoryProviderTests
```

Expected: The build fails because `ClipboardReading.imageMetadata()`, the store-backed provider initializer, the history-change callback, and feature gating do not exist yet.

- [x] **Step 3: Replace ClipboardHistoryProvider**

Replace `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift` with:

```swift
import AppKit
import Foundation
import UniformTypeIdentifiers

protocol ClipboardReading {
    var changeCount: Int { get }
    func string() -> String?
    func imageMetadata() -> ClipboardImageMetadata?
    func setString(_ text: String)
}

final class SystemClipboardReader: ClipboardReading {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func string() -> String? {
        pasteboard.string(forType: .string)
    }

    func imageMetadata() -> ClipboardImageMetadata? {
        let preferredTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        guard let type = preferredTypes.first(where: { pasteboard.data(forType: $0) != nil }),
              let data = pasteboard.data(forType: type),
              let image = NSImage(data: data) else {
            return nil
        }

        let pixelSize = image.representations.first.map {
            (width: $0.pixelsWide, height: $0.pixelsHigh)
        } ?? (width: Int(image.size.width), height: Int(image.size.height))

        return ClipboardImageMetadata(
            typeIdentifier: type.rawValue,
            pixelWidth: pixelSize.width,
            pixelHeight: pixelSize.height,
            byteCount: data.count
        )
    }

    func setString(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

final class ClipboardHistoryProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let reader: ClipboardReading
    private let store: ClipboardHistoryStoring
    private let isEnabled: () -> Bool
    private let dateProvider: () -> Date
    private let onHistoryChanged: () -> Void
    private var lastChangeCount: Int?

    init(
        reader: ClipboardReading = SystemClipboardReader(),
        store: ClipboardHistoryStoring = ClipboardHistoryStore(),
        isEnabled: @escaping () -> Bool = { false },
        dateProvider: @escaping () -> Date = Date.init,
        onHistoryChanged: @escaping () -> Void = {}
    ) {
        self.reader = reader
        self.store = store
        self.isEnabled = isEnabled
        self.dateProvider = dateProvider
        self.onHistoryChanged = onHistoryChanged
    }

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }
        captureCurrentClipboard()

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let matches = q.localizedCaseInsensitiveContains("clip") ? store.items() : store.search(q)
        return matches
            .prefix(Self.maxResultsCount)
            .map(command)
    }

    func captureCurrentClipboard() {
        guard isEnabled() else { return }

        let currentChangeCount = reader.changeCount
        guard lastChangeCount != currentChangeCount else { return }
        lastChangeCount = currentChangeCount

        if let text = reader.string(),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.addText(text, capturedAt: dateProvider())
            onHistoryChanged()
            return
        }

        if let metadata = reader.imageMetadata() {
            store.addImageMetadata(metadata, capturedAt: dateProvider())
            onHistoryChanged()
        }
    }

    private func command(for item: ClipboardHistoryItem) -> PaletteCommand {
        switch item.content {
        case .text(let text):
            return PaletteCommand(
                id: item.id,
                title: item.displayTitle,
                subtitle: "Copy from clipboard history",
                icon: .sfSymbol("doc.on.clipboard"),
                keywords: ["clipboard", "copy", text],
                action: .execute { [reader] in
                    reader.setString(text)
                },
                category: "Clipboard"
            )
        case .image:
            return PaletteCommand(
                id: item.id,
                title: item.displayTitle,
                subtitle: "Image metadata only",
                icon: .sfSymbol("photo"),
                keywords: ["clipboard", "image", item.searchableText],
                action: .execute {},
                category: "Clipboard"
            )
        }
    }
}
```

- [x] **Step 4: Update SnippetsProvider fake clipboard**

In `platforms/macos/AtlasTests/SnippetsProviderTests.swift`, update `FakeSnippetClipboard` so it still conforms to `ClipboardReading` after the protocol gains image metadata:

```swift
private final class FakeSnippetClipboard: ClipboardReading {
    private(set) var changeCount = 0
    private(set) var writtenText: String?

    func string() -> String? {
        writtenText
    }

    func imageMetadata() -> ClipboardImageMetadata? {
        nil
    }

    func setString(_ text: String) {
        writtenText = text
        changeCount += 1
    }
}
```

- [x] **Step 5: Verify provider and snippet tests pass**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/ClipboardHistoryProviderTests \
  -only-testing:AtlasTests/SnippetsProviderTests
```

Expected: `ClipboardHistoryProviderTests` passes, including `testCaptureNotifiesPanelReloadCallback`, and `SnippetsProviderTests` still compiles and passes with the updated fake clipboard.

- [x] **Step 6: Commit provider**

Run:

```bash
git add platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift \
  platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift \
  platforms/macos/AtlasTests/SnippetsProviderTests.swift
git commit -m "feat: back clipboard provider with history store"
```

Expected: The commit contains provider changes, provider-test changes, and the `FakeSnippetClipboard.imageMetadata() -> nil` compatibility update.

---

### Task 4: Clipboard History Panel and Feature Gating

**Files:**
- Create: `platforms/macos/Atlas/ClipboardHistoryPanel.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Create ClipboardHistoryPanel**

Create `platforms/macos/Atlas/ClipboardHistoryPanel.swift`:

```swift
import SwiftUI

struct ClipboardHistoryPanel: View {
    let items: [ClipboardHistoryItem]
    let onCopyText: (String) -> Void
    let onDelete: (UUID) -> Void
    let onClear: () -> Void
    @Binding var query: String

    private var filteredItems: [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.searchableText.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clipboard History")
                    .font(.headline)
                Spacer()
                Button("Clear All", action: onClear)
                    .disabled(items.isEmpty)
            }

            Text("Atlas stores copied text locally on this Mac. Images are recorded as metadata only; image pixels are not saved.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search clipboard history", text: $query)
                .textFieldStyle(.roundedBorder)

            if filteredItems.isEmpty {
                Text(query.isEmpty ? "No clipboard history yet." : "No matching clipboard items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(filteredItems) { item in
                        ClipboardHistoryRow(
                            item: item,
                            onCopyText: onCopyText,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let onCopyText: (String) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.textValue == nil ? "photo" : "doc.on.clipboard")
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let text = item.textValue {
                Button("Copy") {
                    onCopyText(text)
                }
            }

            Button("Delete") {
                onDelete(item.id)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subtitle: String {
        switch item.content {
        case .text(let text):
            return "\(text.count) characters"
        case .image(let metadata):
            if let byteCount = metadata.byteCount {
                return "\(metadata.typeIdentifier), \(byteCount) bytes, pixels not stored"
            }
            return "\(metadata.typeIdentifier), pixels not stored"
        }
    }
}
```

- [x] **Step 2: Add the panel file to the Xcode project**

Run:

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('platforms/macos/Atlas.xcodeproj')
target = proj.targets.find { |t| t.name == 'Atlas' }
group = proj.main_group['Atlas']
unless group.files.any? { |f| f.path == 'ClipboardHistoryPanel.swift' }
  ref = group.new_file('ClipboardHistoryPanel.swift')
  target.source_build_phase.add_file_reference(ref)
end
proj.save
"
```

- [x] **Step 3: Wire shared ClipboardHistoryStore into ContentView**

In `platforms/macos/Atlas/ContentView.swift`, add state near the existing screenshot library state:

```swift
@State private var clipboardHistoryItems: [ClipboardHistoryItem] = []
@State private var clipboardHistoryQuery: String = ""
```

Add a fallback store and computed store near the existing store properties. The fallback is only used in previews or tests where `paletteState` is nil; the running app uses the shared store owned by `CommandPaletteState`.

```swift
private let fallbackClipboardHistoryStore = ClipboardHistoryStore()

private var clipboardHistoryStore: ClipboardHistoryStoring {
    paletteState?.clipboardHistoryStore ?? fallbackClipboardHistoryStore
}
```

In `startModules()`, after `enabledFeatures = FeatureStateReducer.enabledMap(from: loadedFeatures)`, add:

```swift
syncClipboardFeatureGate()
loadClipboardHistory()
```

In `refreshFeature(_ feature:enabled:)`, after updating `features`, add:

```swift
if feature == AtlasModule.clipboard.featureName {
    syncClipboardFeatureGate()
    loadClipboardHistory()
    return
}
```

In the main `VStack`, place this block after the monitoring section and before `FeatureCenterPanel`:

```swift
if isFeatureEnabled(.clipboard) {
    ClipboardHistoryPanel(
        items: clipboardHistoryItems,
        onCopyText: copyClipboardHistoryText,
        onDelete: deleteClipboardHistoryItem,
        onClear: clearClipboardHistory,
        query: $clipboardHistoryQuery
    )

    Divider()
}
```

Add these methods near the other small feature helpers:

```swift
private func loadClipboardHistory() {
    clipboardHistoryItems = clipboardHistoryStore.items()
}

private func copyClipboardHistoryText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    showStatus("Copied clipboard item")
}

private func deleteClipboardHistoryItem(_ id: UUID) {
    clipboardHistoryStore.delete(id: id)
    loadClipboardHistory()
    showStatus("Clipboard item deleted")
}

private func clearClipboardHistory() {
    clipboardHistoryStore.clear()
    loadClipboardHistory()
    showStatus("Clipboard history cleared")
}

private func syncClipboardFeatureGate() {
    paletteState?.setClipboardHistoryEnabled(isFeatureEnabled(.clipboard))
    paletteState?.setClipboardHistoryChangedHandler {
        self.loadClipboardHistory()
    }
}
```

- [x] **Step 4: Wire shared store and command palette gating in AtlasApp**

In `platforms/macos/Atlas/AtlasApp.swift`, add shared store and provider properties to `CommandPaletteState`:

```swift
let clipboardHistoryStore = ClipboardHistoryStore()
private lazy var clipboardHistoryProvider = ClipboardHistoryProvider(store: clipboardHistoryStore)
```

Remove the local `let clipboardHistoryProvider = ClipboardHistoryProvider()` from `init()` and keep the existing provider order using the property:

```swift
self.controller = CommandPaletteController(providers: [
    atlasProvider,
    developerToolsProvider,
    windowManagementProvider,
    clipboardHistoryProvider,
    snippetsProvider,
    appLauncherProvider,
])
```

Add this method to `CommandPaletteState`:

```swift
func setClipboardHistoryEnabled(_ enabled: Bool) {
    clipboardHistoryProvider.setEnabled(enabled)
}

func setClipboardHistoryChangedHandler(_ handler: @escaping () -> Void) {
    clipboardHistoryProvider.setHistoryChangedHandler(handler)
}
```

In `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift`, support mutable feature state and a mutable history-change callback by replacing these properties:

```swift
private var enabled: Bool
private var onHistoryChanged: () -> Void
```

Update the initializer signature:

```swift
init(
    reader: ClipboardReading = SystemClipboardReader(),
    store: ClipboardHistoryStoring = ClipboardHistoryStore(),
    isEnabled: @escaping () -> Bool = { false },
    dateProvider: @escaping () -> Date = Date.init,
    onHistoryChanged: @escaping () -> Void = {}
) {
    self.reader = reader
    self.store = store
    self.enabled = isEnabled()
    self.dateProvider = dateProvider
    self.onHistoryChanged = onHistoryChanged
}
```

Add these methods:

```swift
func setEnabled(_ enabled: Bool) {
    self.enabled = enabled
}

func setHistoryChangedHandler(_ handler: @escaping () -> Void) {
    self.onHistoryChanged = handler
}
```

Replace `guard isEnabled() else { return [] }` and `guard isEnabled() else { return }` with:

```swift
guard enabled else { return [] }
```

and:

```swift
guard enabled else { return }
```

- [x] **Step 5: Build the app**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS'
```

Expected: The app builds. The Clipboard History panel compiles and is available only when the `clipboard` feature is enabled.

- [x] **Step 6: Commit UI and gating**

Run:

```bash
git add platforms/macos/Atlas/ClipboardHistoryPanel.swift \
  platforms/macos/Atlas/ContentView.swift \
  platforms/macos/Atlas/AtlasApp.swift \
  platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: gate clipboard history UI"
```

Expected: The commit includes panel UI, feature gating, provider enablement, and explicit PBX membership for the new panel file.

---

### Task 5: Final Verification

**Files:**
- Verify: `crates/atlas-core/src/features.rs`
- Verify: `platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift`
- Verify: `platforms/macos/Atlas/ClipboardHistoryStore.swift`
- Verify: `platforms/macos/Atlas/ClipboardHistoryPanel.swift`
- Verify: `platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift`
- Verify: `platforms/macos/AtlasTests/ClipboardHistoryStoreTests.swift`
- Verify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Run focused Rust feature tests**

Run:

```bash
cargo test -p atlas-core test_feature_toggle
cargo test -p atlas-core test_toggle_non_existent_feature
cargo test -p atlas-core test_list_features_is_sorted_by_name
```

Expected: All three Rust commands pass.

- [x] **Step 2: Run focused Swift clipboard and feature tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/ClipboardHistoryStoreTests \
  -only-testing:AtlasTests/ClipboardHistoryProviderTests \
  -only-testing:AtlasTests/FeatureModelsTests
```

Expected: Clipboard store, provider, and feature model tests pass.

- [x] **Step 3: Run command palette regression tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS' \
  -only-testing:AtlasTests/CommandPaletteModelsTests \
  -only-testing:AtlasTests/AtlasCommandProviderTests \
  -only-testing:AtlasTests/CommandPaletteRankerTests \
  -only-testing:AtlasTests/CommandUsageStoreTests \
  -only-testing:AtlasTests/AppLauncherProviderTests \
  -only-testing:AtlasTests/DeveloperToolsProviderTests \
  -only-testing:AtlasTests/SnippetsProviderTests \
  -only-testing:AtlasTests/WindowManagementProviderTests \
  -only-testing:AtlasTests/ClipboardHistoryProviderTests
```

Expected: Command palette tests pass with clipboard history still ordered between Window Management and Snippets.

- [x] **Step 4: Build the macOS app**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=macOS'
```

Expected: The app builds successfully.

- [x] **Step 5: Inspect project membership and diff**

Run:

```bash
rg -n 'ClipboardHistoryStore|ClipboardHistoryPanel|ClipboardHistoryStoreTests|ClipboardHistoryProviderTests' \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git diff --stat
git diff -- crates/atlas-core/src/features.rs \
  platforms/macos/Atlas/CommandPalette/ClipboardHistoryProvider.swift \
  platforms/macos/Atlas/ClipboardHistoryStore.swift \
  platforms/macos/Atlas/ClipboardHistoryPanel.swift \
  platforms/macos/AtlasTests/ClipboardHistoryProviderTests.swift \
  platforms/macos/AtlasTests/ClipboardHistoryStoreTests.swift \
  platforms/macos/Atlas/ContentView.swift \
  platforms/macos/Atlas/AtlasApp.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: The PBX file contains source references and build-phase entries for each new Swift app/test file, and the diff is limited to clipboard feature implementation files.

- [x] **Step 6: Commit final verification note if needed**

If any plan checklist or execution note is updated during implementation, run:

```bash
git add docs/superpowers/plans/2026-05-22-clipboard-history-v1.md
git commit -m "docs: record clipboard history verification"
```

Expected: This commit is only needed if the implementation worker records factual execution notes in this plan.

## Acceptance Criteria

- The `clipboard` feature appears in Feature Center as `Clipboard History` and defaults disabled.
- When `clipboard` is disabled, command palette clipboard history performs no pasteboard reads and returns no results.
- When enabled, text clipboard entries persist across store instances.
- When the command palette captures a clipboard item while the panel is visible, the shared store plus `onHistoryChanged` callback reloads panel state without restarting the app.
- Image clipboard entries persist only metadata: type identifier, dimensions, and optional byte count.
- The panel states that text is stored locally and image pixels are not stored.
- Search works for text content and image metadata.
- Individual delete and clear-all update persisted history.
- Max retention keeps only the newest configured entries.
- New Swift files are present in `platforms/macos/Atlas.xcodeproj/project.pbxproj` and assigned to the correct targets.
- Focused Rust, Swift clipboard, FeatureModels, command palette regression tests, and macOS app build pass.
