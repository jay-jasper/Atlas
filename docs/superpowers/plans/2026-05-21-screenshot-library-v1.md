# Screenshot Library v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local screenshot library that automatically indexes captured screenshots and lets users search saved screenshots by recognized or translated text.

**Architecture:** Keep storage in the macOS layer for this version: write PNG files under Application Support and persist a compact JSON index beside them. `ContentView` records new captures, updates index text after OCR/translation succeeds, and renders a lightweight SwiftUI library panel that can reopen indexed screenshots in the existing editor.

**Tech Stack:** SwiftUI, AppKit, XCTest, Foundation `FileManager`, JSON `Codable`, existing Atlas macOS Xcode project.

---

## Scope

This plan implements Screenshot Library v1:

- Automatically save each captured screenshot into a local library directory.
- Persist metadata in a JSON index:
  - id
  - PNG filename
  - capture timestamp
  - pixel width and height
  - capture source label
  - recognized OCR text
  - translated text
- Update the library item when OCR or translation completes.
- Provide a searchable in-app library panel.
- Reopen a library item in the existing screenshot editor.
- Delete a library item and its PNG file.

Out of scope for v1:

- SQLite storage. The product spec eventually calls for SQLite, but JSON is sufficient for the first local-only implementation and avoids introducing a migration surface before the data model stabilizes.
- Cloud sync.
- Thumbnail generation.
- Screenshot tagging.
- Background OCR for old captures.
- Manual UI verification. The user preference is unit tests only.
- Rust/FFI changes.

## File Structure

- `platforms/macos/Atlas/ScreenshotLibrary.swift`
  - Owns `ScreenshotLibraryItem`, `ScreenshotLibraryStore`, store errors, JSON index loading/saving, PNG file writes, search, update, and delete.
- `platforms/macos/Atlas/ScreenshotLibraryPanel.swift`
  - SwiftUI panel for search, counts, item rows, open action, and delete action.
- `platforms/macos/Atlas/ContentView.swift`
  - Records library items on capture, refreshes library state, updates OCR/translation text, and reopens selected items.
- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new Swift source and test files.
- `platforms/macos/AtlasTests/ScreenshotLibraryTests.swift`
  - Unit tests for store add/load/search/update/delete and file persistence.
- `platforms/macos/AtlasTests/ScreenshotLibraryPanelTests.swift`
  - Unit tests for panel state filtering/count display.

---

### Task 1: Screenshot Library Store

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotLibrary.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotLibraryTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing store tests**

Create `platforms/macos/AtlasTests/ScreenshotLibraryTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScreenshotLibraryTests: XCTestCase {
    private var rootDirectory: URL!
    private var store: ScreenshotLibraryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotLibraryTests-\(UUID().uuidString)", isDirectory: true)
        store = ScreenshotLibraryStore(rootDirectory: rootDirectory)
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        store = nil
        rootDirectory = nil
        try super.tearDownWithError()
    }

    func testLoadItemsReturnsEmptyArrayBeforeIndexExists() throws {
        XCTAssertEqual(try store.loadItems(), [])
    }

    func testAddScreenshotWritesPngAndIndexEntry() throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let capturedAt = Date(timeIntervalSince1970: 1_704_067_200)

        let item = try store.addScreenshot(
            pngData: pngData,
            pixelWidth: 320,
            pixelHeight: 200,
            source: "Window",
            capturedAt: capturedAt
        )

        XCTAssertEqual(item.pixelWidth, 320)
        XCTAssertEqual(item.pixelHeight, 200)
        XCTAssertEqual(item.source, "Window")
        XCTAssertEqual(item.recognizedText, "")
        XCTAssertEqual(item.translatedText, "")
        XCTAssertEqual(try Data(contentsOf: store.pngURL(for: item)), pngData)
        XCTAssertEqual(try store.loadItems(), [item])
    }

    func testLoadItemsSortsNewestFirst() throws {
        let older = try store.addScreenshot(
            pngData: Data([1]),
            pixelWidth: 10,
            pixelHeight: 10,
            source: "Desktop",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = try store.addScreenshot(
            pngData: Data([2]),
            pixelWidth: 20,
            pixelHeight: 20,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(try store.loadItems().map(\\.id), [newer.id, older.id])
    }

    func testUpdateRecognizedAndTranslatedText() throws {
        let item = try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            pixelWidth: 120,
            pixelHeight: 80,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 10)
        )

        try store.updateText(
            id: item.id,
            recognizedText: "Hello Atlas",
            translatedText: "你好 Atlas"
        )

        let updated = try XCTUnwrap(store.loadItems().first)
        XCTAssertEqual(updated.recognizedText, "Hello Atlas")
        XCTAssertEqual(updated.translatedText, "你好 Atlas")
    }

    func testUpdateTextPreservesNilFields() throws {
        let item = try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            pixelWidth: 120,
            pixelHeight: 80,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 10)
        )

        try store.updateText(id: item.id, recognizedText: "Alpha", translatedText: "Beta")
        try store.updateText(id: item.id, recognizedText: nil, translatedText: "Gamma")

        let updated = try XCTUnwrap(store.loadItems().first)
        XCTAssertEqual(updated.recognizedText, "Alpha")
        XCTAssertEqual(updated.translatedText, "Gamma")
    }

    func testSearchMatchesSourceRecognizedAndTranslatedTextCaseInsensitively() throws {
        _ = try store.addScreenshot(
            pngData: Data([1]),
            pixelWidth: 100,
            pixelHeight: 100,
            source: "Desktop",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let invoice = try store.addScreenshot(
            pngData: Data([2]),
            pixelWidth: 200,
            pixelHeight: 100,
            source: "Window",
            capturedAt: Date(timeIntervalSince1970: 20)
        )
        try store.updateText(
            id: invoice.id,
            recognizedText: "Invoice total due",
            translatedText: "发票总额"
        )

        XCTAssertEqual(try store.search(query: "invoice").map(\\.id), [invoice.id])
        XCTAssertEqual(try store.search(query: "发票").map(\\.id), [invoice.id])
        XCTAssertEqual(try store.search(query: "window").map(\\.id), [invoice.id])
        XCTAssertEqual(try store.search(query: "missing"), [])
    }

    func testBlankSearchReturnsAllItemsNewestFirst() throws {
        let first = try store.addScreenshot(
            pngData: Data([1]),
            pixelWidth: 10,
            pixelHeight: 10,
            source: "Desktop",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let second = try store.addScreenshot(
            pngData: Data([2]),
            pixelWidth: 20,
            pixelHeight: 20,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(try store.search(query: "   ").map(\\.id), [second.id, first.id])
    }

    func testDeleteRemovesIndexEntryAndPngFile() throws {
        let item = try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            pixelWidth: 120,
            pixelHeight: 80,
            source: "Area",
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        let pngURL = store.pngURL(for: item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pngURL.path))

        try store.delete(id: item.id)

        XCTAssertEqual(try store.loadItems(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: pngURL.path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotLibraryTests
```

Expected: FAIL because `ScreenshotLibraryStore` and `ScreenshotLibraryItem` do not exist yet.

- [ ] **Step 3: Add store implementation**

Create `platforms/macos/Atlas/ScreenshotLibrary.swift`:

```swift
import Foundation

enum ScreenshotLibraryError: LocalizedError, Equatable {
    case missingImage(UUID)

    var errorDescription: String? {
        switch self {
        case .missingImage:
            return "Screenshot image is missing from the local library"
        }
    }
}

struct ScreenshotLibraryItem: Codable, Identifiable, Equatable {
    let id: UUID
    var filename: String
    var capturedAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
    var source: String
    var recognizedText: String
    var translatedText: String

    var dimensionsText: String {
        "\(pixelWidth) x \(pixelHeight)"
    }
}

struct ScreenshotLibraryStore {
    private let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory ?? ScreenshotLibraryStore.defaultRootDirectory(fileManager: fileManager)
        self.fileManager = fileManager
    }

    static func defaultRootDirectory(fileManager: FileManager = .default) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("Screenshot Library", isDirectory: true)
    }

    func loadItems() throws -> [ScreenshotLibraryItem] {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexURL)
        let items = try JSONDecoder.screenshotLibrary.decode([ScreenshotLibraryItem].self, from: data)
        return sorted(items)
    }

    func addScreenshot(
        pngData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        source: String,
        capturedAt: Date = Date()
    ) throws -> ScreenshotLibraryItem {
        try ensureDirectories()

        let id = UUID()
        let filename = "\(id.uuidString).png"
        let item = ScreenshotLibraryItem(
            id: id,
            filename: filename,
            capturedAt: capturedAt,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            source: source,
            recognizedText: "",
            translatedText: ""
        )

        try pngData.write(to: pngURL(for: item), options: .atomic)
        var items = try loadItems()
        items.append(item)
        try saveItems(items)
        return item
    }

    func updateText(
        id: UUID,
        recognizedText: String?,
        translatedText: String?
    ) throws {
        var items = try loadItems()

        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        if let recognizedText {
            items[index].recognizedText = recognizedText
        }

        if let translatedText {
            items[index].translatedText = translatedText
        }

        try saveItems(items)
    }

    func search(query: String) throws -> [ScreenshotLibraryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = try loadItems()

        guard !trimmedQuery.isEmpty else {
            return items
        }

        return items.filter { item in
            item.source.localizedCaseInsensitiveContains(trimmedQuery)
                || item.recognizedText.localizedCaseInsensitiveContains(trimmedQuery)
                || item.translatedText.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    func delete(id: UUID) throws {
        var items = try loadItems()
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let item = items.remove(at: index)
        let imageURL = pngURL(for: item)
        if fileManager.fileExists(atPath: imageURL.path) {
            try fileManager.removeItem(at: imageURL)
        }

        try saveItems(items)
    }

    func pngURL(for item: ScreenshotLibraryItem) -> URL {
        imagesDirectory.appendingPathComponent(item.filename)
    }

    func pngData(for item: ScreenshotLibraryItem) throws -> Data {
        let url = pngURL(for: item)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ScreenshotLibraryError.missingImage(item.id)
        }
        return try Data(contentsOf: url)
    }

    private var imagesDirectory: URL {
        rootDirectory.appendingPathComponent("Images", isDirectory: true)
    }

    private var indexURL: URL {
        rootDirectory.appendingPathComponent("index.json")
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    private func saveItems(_ items: [ScreenshotLibraryItem]) throws {
        try ensureDirectories()
        let data = try JSONEncoder.screenshotLibrary.encode(sorted(items))
        try data.write(to: indexURL, options: .atomic)
    }

    private func sorted(_ items: [ScreenshotLibraryItem]) -> [ScreenshotLibraryItem] {
        items.sorted { lhs, rhs in
            if lhs.capturedAt == rhs.capturedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.capturedAt > rhs.capturedAt
        }
    }
}

private extension JSONEncoder {
    static var screenshotLibrary: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var screenshotLibrary: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 4: Add files to the Xcode project**

Modify `platforms/macos/Atlas.xcodeproj/project.pbxproj`:

- Add `ScreenshotLibrary.swift` to the `Atlas` group and app target `Sources`.
- Add `ScreenshotLibraryTests.swift` to the `AtlasTests` group and test target `Sources`.
- Use new unique 24-character hex IDs following the existing `83CBBB...` formatting.
- Do not reorder unrelated project entries or change build settings.

- [ ] **Step 5: Run store tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotLibraryTests
```

Expected: PASS with 8 tests.

- [ ] **Step 6: Commit store**

```bash
git add platforms/macos/Atlas/ScreenshotLibrary.swift platforms/macos/AtlasTests/ScreenshotLibraryTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add screenshot library store"
```

---

### Task 2: Screenshot Library Panel

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotLibraryPanel.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotLibraryPanelTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing panel state tests**

Create `platforms/macos/AtlasTests/ScreenshotLibraryPanelTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScreenshotLibraryPanelTests: XCTestCase {
    func testStateShowsEmptyTextWhenLibraryIsEmpty() {
        let state = ScreenshotLibraryPanelState(items: [], query: "")

        XCTAssertEqual(state.visibleItems, [])
        XCTAssertEqual(state.countText, "0 screenshots")
        XCTAssertEqual(state.emptyText, "No screenshots saved yet")
    }

    func testStateFiltersByRecognizedText() {
        let first = item(source: "Desktop", recognizedText: "Build failed", translatedText: "")
        let second = item(source: "Window", recognizedText: "Invoice total", translatedText: "")

        let state = ScreenshotLibraryPanelState(items: [first, second], query: "invoice")

        XCTAssertEqual(state.visibleItems, [second])
        XCTAssertEqual(state.countText, "1 of 2 screenshots")
        XCTAssertEqual(state.emptyText, "No screenshots match the search")
    }

    func testStateFiltersByTranslatedTextAndSource() {
        let first = item(source: "Desktop", recognizedText: "", translatedText: "错误日志")
        let second = item(source: "Area", recognizedText: "", translatedText: "付款")

        XCTAssertEqual(
            ScreenshotLibraryPanelState(items: [first, second], query: "错误").visibleItems,
            [first]
        )
        XCTAssertEqual(
            ScreenshotLibraryPanelState(items: [first, second], query: "area").visibleItems,
            [second]
        )
    }

    func testStateUsesNewestInputOrderWithoutResorting() {
        let first = item(source: "Desktop", capturedAt: Date(timeIntervalSince1970: 20))
        let second = item(source: "Area", capturedAt: Date(timeIntervalSince1970: 10))

        let state = ScreenshotLibraryPanelState(items: [first, second], query: "")

        XCTAssertEqual(state.visibleItems, [first, second])
    }

    private func item(
        source: String,
        recognizedText: String = "",
        translatedText: String = "",
        capturedAt: Date = Date(timeIntervalSince1970: 10)
    ) -> ScreenshotLibraryItem {
        ScreenshotLibraryItem(
            id: UUID(),
            filename: "\(UUID().uuidString).png",
            capturedAt: capturedAt,
            pixelWidth: 120,
            pixelHeight: 80,
            source: source,
            recognizedText: recognizedText,
            translatedText: translatedText
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotLibraryPanelTests
```

Expected: FAIL because `ScreenshotLibraryPanelState` and `ScreenshotLibraryPanel` do not exist.

- [ ] **Step 3: Add panel implementation**

Create `platforms/macos/Atlas/ScreenshotLibraryPanel.swift`:

```swift
import SwiftUI

struct ScreenshotLibraryPanelState: Equatable {
    let items: [ScreenshotLibraryItem]
    let query: String

    var visibleItems: [ScreenshotLibraryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        return items.filter { item in
            item.source.localizedCaseInsensitiveContains(trimmedQuery)
                || item.recognizedText.localizedCaseInsensitiveContains(trimmedQuery)
                || item.translatedText.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var countText: String {
        if visibleItems.count == items.count {
            return "\(items.count) \(items.count == 1 ? "screenshot" : "screenshots")"
        }
        return "\(visibleItems.count) of \(items.count) screenshots"
    }

    var emptyText: String {
        items.isEmpty ? "No screenshots saved yet" : "No screenshots match the search"
    }
}

struct ScreenshotLibraryPanel: View {
    let items: [ScreenshotLibraryItem]
    let onOpen: (ScreenshotLibraryItem) -> Void
    let onDelete: (ScreenshotLibraryItem) -> Void

    @Binding var query: String

    var body: some View {
        let state = ScreenshotLibraryPanelState(items: items, query: query)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Screenshot Library")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(state.countText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField("Search screenshots", text: $query)
                .textFieldStyle(.roundedBorder)

            if state.visibleItems.isEmpty {
                Text(state.emptyText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(state.visibleItems) { item in
                        ScreenshotLibraryRow(
                            item: item,
                            onOpen: { onOpen(item) },
                            onDelete: { onDelete(item) }
                        )
                    }
                }
            }
        }
    }
}

private struct ScreenshotLibraryRow: View {
    let item: ScreenshotLibraryItem
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "photo")
                .foregroundColor(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.source)
                    Text(item.dimensionsText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(Self.dateFormatter.string(from: item.capturedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !item.recognizedText.isEmpty {
                    Text(item.recognizedText)
                        .font(.caption)
                        .lineLimit(2)
                }

                if !item.translatedText.isEmpty {
                    Text(item.translatedText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onOpen) {
                Image(systemName: "arrow.up.right.square")
            }
            .help("Open")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .help("Delete")
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
```

- [ ] **Step 4: Add files to the Xcode project**

Modify `platforms/macos/Atlas.xcodeproj/project.pbxproj`:

- Add `ScreenshotLibraryPanel.swift` to the `Atlas` group and app target `Sources`.
- Add `ScreenshotLibraryPanelTests.swift` to the `AtlasTests` group and test target `Sources`.
- Use new unique 24-character hex IDs following the surrounding entries.

- [ ] **Step 5: Run panel tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotLibraryPanelTests
```

Expected: PASS with 4 tests.

- [ ] **Step 6: Commit panel**

```bash
git add platforms/macos/Atlas/ScreenshotLibraryPanel.swift platforms/macos/AtlasTests/ScreenshotLibraryPanelTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add screenshot library panel"
```

---

### Task 3: Wire Library Into Capture, OCR, Translation, and Open/Delete Actions

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Add library state and store to `ContentView`**

Modify `platforms/macos/Atlas/ContentView.swift` near the existing screenshot state:

```swift
@State private var screenshotLibraryItems: [ScreenshotLibraryItem] = []
@State private var screenshotLibraryQuery: String = ""
@State private var activeLibraryItemID: UUID?
private let screenshotLibraryStore = ScreenshotLibraryStore()
```

- [ ] **Step 2: Render the library panel**

Insert this panel after `ScreenshotFeatureSettingsPanel` and before `TranslationSettingsPanel`:

```swift
ScreenshotLibraryPanel(
    items: screenshotLibraryItems,
    onOpen: openLibraryItem,
    onDelete: deleteLibraryItem,
    query: $screenshotLibraryQuery
)

Divider()
```

- [ ] **Step 3: Load library state at startup**

Modify `startModules()` so it loads screenshot settings, translation settings, and library state:

```swift
private func startModules() {
    loadScreenshotFeatureSettings()
    loadTranslationSettings()
    loadScreenshotLibrary()

    do {
        let loadedFeatures = try AtlasBridge.listFeatures()
        features = loadedFeatures
        enabledFeatures = FeatureStateReducer.enabledMap(from: loadedFeatures)
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

- [ ] **Step 4: Add library helper methods**

Add these private methods near the existing screenshot helpers:

```swift
private func loadScreenshotLibrary() {
    do {
        screenshotLibraryItems = try screenshotLibraryStore.loadItems()
    } catch {
        showStatus(error.localizedDescription, kind: .error, autoHide: false)
    }
}

private func recordScreenshotInLibrary(_ screenshot: CapturedScreenshot, source: String) {
    do {
        let item = try screenshotLibraryStore.addScreenshot(
            pngData: screenshot.pngData,
            pixelWidth: Int(screenshot.rect.width),
            pixelHeight: Int(screenshot.rect.height),
            source: source,
            capturedAt: screenshot.capturedAt
        )
        activeLibraryItemID = item.id
        loadScreenshotLibrary()
    } catch {
        activeLibraryItemID = nil
        showStatus(error.localizedDescription, kind: .error, autoHide: false)
    }
}

private func updateActiveLibraryItem(
    recognizedText: String? = nil,
    translatedText: String? = nil
) {
    guard let activeLibraryItemID else { return }

    do {
        try screenshotLibraryStore.updateText(
            id: activeLibraryItemID,
            recognizedText: recognizedText,
            translatedText: translatedText
        )
        loadScreenshotLibrary()
    } catch {
        showStatus(error.localizedDescription, kind: .error, autoHide: false)
    }
}

private func openLibraryItem(_ item: ScreenshotLibraryItem) {
    do {
        let data = try screenshotLibraryStore.pngData(for: item)
        let rect = CGRect(x: 0, y: 0, width: item.pixelWidth, height: item.pixelHeight)
        activeLibraryItemID = item.id
        capturedScreenshot = CapturedScreenshot(
            id: item.id,
            pngData: data,
            rect: rect,
            capturedAt: item.capturedAt
        )
        recognizedScreenshotText = item.recognizedText
        translatedScreenshotText = item.translatedText
        isRecognizingScreenshotText = false
        isTranslatingScreenshotText = false
    } catch {
        showStatus(error.localizedDescription, kind: .error)
    }
}

private func deleteLibraryItem(_ item: ScreenshotLibraryItem) {
    do {
        try screenshotLibraryStore.delete(id: item.id)
        if activeLibraryItemID == item.id {
            closeScreenshotEditor()
        }
        loadScreenshotLibrary()
        showStatus("Deleted screenshot")
    } catch {
        showStatus(error.localizedDescription, kind: .error)
    }
}
```

- [ ] **Step 5: Record captures with source labels**

Change capture completion call sites:

In `captureWindow(_:)`, replace:

```swift
setCapturedScreenshot(CapturedScreenshot(pngData: data, rect: rect))
```

with:

```swift
setCapturedScreenshot(CapturedScreenshot(pngData: data, rect: rect), source: "Window")
```

In `captureSelection(_:)`, replace:

```swift
setCapturedScreenshot(CapturedScreenshot(pngData: data, rect: pixelRect))
```

with:

```swift
setCapturedScreenshot(CapturedScreenshot(pngData: data, rect: pixelRect), source: "Area")
```

In `captureDesktop()`, replace:

```swift
setCapturedScreenshot(CapturedScreenshot(pngData: data, rect: rect))
```

with:

```swift
setCapturedScreenshot(CapturedScreenshot(pngData: data, rect: rect), source: "Desktop")
```

- [ ] **Step 6: Update `setCapturedScreenshot`**

Replace:

```swift
private func setCapturedScreenshot(_ screenshot: CapturedScreenshot) {
    invalidateScreenshotTextTasks()
    capturedScreenshot = screenshot
    clearScreenshotTextState()
}
```

with:

```swift
private func setCapturedScreenshot(_ screenshot: CapturedScreenshot, source: String) {
    invalidateScreenshotTextTasks()
    capturedScreenshot = screenshot
    clearScreenshotTextState()
    recordScreenshotInLibrary(screenshot, source: source)
}
```

- [ ] **Step 7: Clear active library item when the editor closes**

Update `closeScreenshotEditor()` to clear `activeLibraryItemID`:

```swift
private func closeScreenshotEditor() {
    invalidateScreenshotTextTasks()
    capturedScreenshot = nil
    activeLibraryItemID = nil
    clearScreenshotTextState()
}
```

- [ ] **Step 8: Update library text after OCR success**

In `recognizeScreenshotText(_:)`, inside `.success(let ocrResult)` after setting `recognizedScreenshotText`, add:

```swift
updateActiveLibraryItem(recognizedText: ocrResult.text)
```

The success block should become:

```swift
case .success(let ocrResult):
    recognizedScreenshotText = ocrResult.text
    updateActiveLibraryItem(recognizedText: ocrResult.text)
    showStatus(ocrResult.text.isEmpty ? "No text found" : "Recognized text")
```

- [ ] **Step 9: Update library text after translation success**

In `translateRecognizedScreenshotText(_:)`, inside `.success(let translationResult)` after setting `translatedScreenshotText`, add:

```swift
updateActiveLibraryItem(translatedText: translationResult.translatedText)
```

The success block should become:

```swift
case .success(let translationResult):
    translatedScreenshotText = translationResult.translatedText
    updateActiveLibraryItem(translatedText: translationResult.translatedText)
    showStatus("Translated text")
```

- [ ] **Step 10: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [ ] **Step 11: Run focused library tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotLibraryTests -only-testing:AtlasTests/ScreenshotLibraryPanelTests
```

Expected: PASS with 12 tests.

- [ ] **Step 12: Commit wiring**

```bash
git add platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): wire screenshot library"
```

---

### Task 4: Final Verification and Plan Notes

**Files:**
- Modify: `docs/superpowers/plans/2026-05-21-screenshot-library-v1.md`

- [x] **Step 1: Run Swift parse**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [x] **Step 2: Run focused screenshot library tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotLibraryTests -only-testing:AtlasTests/ScreenshotLibraryPanelTests
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

Append this section to `docs/superpowers/plans/2026-05-21-screenshot-library-v1.md`:

```markdown
---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
- Focused screenshot library tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotLibraryTests -only-testing:AtlasTests/ScreenshotLibraryPanelTests`
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Rust core tests: `cargo test -p atlas-core`

Screenshot Library v1 intentionally uses local PNG files plus a JSON index. A future SQLite migration can reuse `ScreenshotLibraryItem` fields once search scale and schema needs are clearer.
```

- [x] **Step 6: Commit verification notes**

```bash
git add docs/superpowers/plans/2026-05-21-screenshot-library-v1.md
git commit -m "docs: record screenshot library v1 verification"
```

---

## Verification Notes

- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
- Result: PASS with no output.
- Focused screenshot library tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotLibraryTests -only-testing:AtlasTests/ScreenshotLibraryPanelTests`
- Result: PASS, 19 tests.
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
- Result: PASS, 120 tests. The existing CoreSimulator out-of-date warning was emitted, but `TEST SUCCEEDED` appeared.
- Rust core tests: `cargo test -p atlas-core`
- Result: PASS, 21 tests.

Screenshot Library v1 intentionally uses local PNG files plus a JSON index. A future SQLite migration can reuse `ScreenshotLibraryItem` fields once search scale and schema needs are clearer.

---

## Self-Review

1. **Spec coverage:** This plan implements the first local-only content index: captures are persisted, OCR/translation text is indexed, search can find screenshots by source or text, and users can reopen/delete saved screenshots. SQLite is intentionally deferred and called out as future migration work.
2. **Placeholder scan:** No task uses incomplete placeholder instructions. Every new file includes concrete test or implementation content, and every command includes the expected result.
3. **Type consistency:** `ScreenshotLibraryItem`, `ScreenshotLibraryStore`, `ScreenshotLibraryPanelState`, and `ScreenshotLibraryPanel` are introduced before later tasks use them.
