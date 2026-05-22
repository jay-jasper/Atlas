# Scratchpad v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local Markdown scratchpad with create, edit, delete, command palette access, optional AI summaries, and Feature Center gating.

**Architecture:** Keep Scratchpad in Swift because v1 is a local macOS UI and storage feature. Store notes as Markdown strings in a JSON file under Application Support through a focused `ScratchpadStore`; expose note search/open actions through a command palette provider; inject a `ScratchpadSummarizing` dependency so summary tests do not call a network or model. Register the feature in the existing Rust Feature Center registry so disabled Scratchpad hides its panel and returns no command palette results.

**Tech Stack:** Swift, SwiftUI, Foundation JSON file storage, XCTest, Rust feature registry, UniFFI feature list/toggle bridge, explicit Xcode PBX project membership.

---

## Scope

This plan implements:

- Local Markdown note storage.
- Create, edit, and delete note workflows.
- Search and open-note access from the command palette.
- Optional AI summary through an injected summarizer.
- Feature Center gating for UI and command palette results.
- XCTest coverage for storage, command palette behavior, summary injection, and feature title mapping.

Out of scope:

- Cloud sync.
- Rich text editing beyond plain Markdown.
- Attachments and images.
- Rust or UniFFI Scratchpad APIs beyond the `scratchpad` feature name.
- Production AI provider selection. The default summarizer is intentionally local/no-op until an AI settings feature exists.

## Current Baseline

The required audit command:

```bash
rg -n 'Scratchpad|scratchpad|note|markdown' platforms/macos/Atlas platforms/macos/AtlasTests docs/superpowers/plans
```

currently shows Scratchpad only in roadmap/planning text. Production matches for `note` are existing snippet fixtures such as `meeting-notes`; they are not a Scratchpad implementation.

## File Map

**New files:**

- `platforms/macos/Atlas/ScratchpadModels.swift`
  - Defines `ScratchpadNote`, `ScratchpadDraft`, and `ScratchpadStoreError`.
- `platforms/macos/Atlas/ScratchpadStore.swift`
  - Defines `ScratchpadStoring` and JSON-backed `ScratchpadStore`.
- `platforms/macos/Atlas/ScratchpadSummaryService.swift`
  - Defines `ScratchpadSummarizing`, `ScratchpadSummaryResult`, and a local `DisabledScratchpadSummarizer`.
- `platforms/macos/Atlas/ScratchpadPanel.swift`
  - SwiftUI editor/list panel for create, edit, delete, and summarize.
- `platforms/macos/Atlas/CommandPalette/ScratchpadProvider.swift`
  - Command palette provider for Scratchpad search and open actions.
- `platforms/macos/AtlasTests/ScratchpadStoreTests.swift`
  - Tests Markdown persistence, validation, update, delete, search, and corruption recovery.
- `platforms/macos/AtlasTests/ScratchpadProviderTests.swift`
  - Tests command palette access and disabled gating.
- `platforms/macos/AtlasTests/ScratchpadSummaryServiceTests.swift`
  - Tests summary injection and disabled default behavior.

**Modified files:**

- `crates/atlas-core/src/features.rs`
  - Registers `scratchpad` as disabled by default and updates sorted feature expectations.
- `platforms/macos/Atlas/AtlasModule.swift`
  - Adds `case scratchpad`.
- `platforms/macos/Atlas/FeatureModels.swift`
  - Maps `scratchpad` to `Scratchpad`.
- `platforms/macos/Atlas/ContentView.swift`
  - Shows `ScratchpadPanel` only when the feature is enabled.
- `platforms/macos/Atlas/AtlasApp.swift`
  - Creates one shared `ScratchpadStore`, wires `ScratchpadProvider`, and exposes `setScratchpadEnabled(_:)`.
- `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`
  - Adds `PaletteDestination.scratchpad(noteID: UUID?)`.
- `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`
  - Adds `scratchpadViewBuilder`.
- `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`
  - Renders the Scratchpad command palette destination.
- `platforms/macos/AtlasTests/FeatureModelsTests.swift`
  - Adds Scratchpad title coverage.
- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds every new Swift app file to the `Atlas` target sources and every new Swift test file to the `AtlasTests` target sources.

Project membership rule: this repo uses explicit PBX project references. Every new Swift file listed above must appear as a `PBXFileReference`, a `PBXBuildFile`, in the correct group, and in the correct `PBXSourcesBuildPhase` before running `xcodebuild test`.

---

### Task 1: Register Scratchpad Feature

**Files:**
- Modify: `crates/atlas-core/src/features.rs`
- Modify: `platforms/macos/Atlas/AtlasModule.swift`
- Modify: `platforms/macos/Atlas/FeatureModels.swift`
- Test: `platforms/macos/AtlasTests/FeatureModelsTests.swift`

- [ ] **Step 1: Add the Rust feature name**

In `crates/atlas-core/src/features.rs`, update `FeatureManager::new()`:

```rust
pub fn new() -> Self {
    let mut features = HashMap::new();
    // Default feature placeholders
    features.insert("monitoring".to_string(), FeatureStatus::Disabled);
    features.insert("scratchpad".to_string(), FeatureStatus::Disabled);
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

    assert_eq!(names, ["monitoring", "scratchpad", "screenshot", "window-manager"]);
}
```

- [ ] **Step 2: Add the Swift module entry**

In `platforms/macos/Atlas/AtlasModule.swift`, add Scratchpad additively:

```swift
enum AtlasModule: String, CaseIterable, Identifiable {
    case scratchpad
    // Preserve every existing case from the file, including cases added by
    // other child plans such as custom automation.
    case screenshot
    case monitoring

    var id: String { rawValue }

    var featureName: String {
        rawValue
    }

    var title: String {
        switch self {
        case .scratchpad:
            return "Scratchpad"
        // Preserve every existing switch branch from the file.
        case .screenshot:
            return "Screenshot"
        case .monitoring:
            return "Monitoring"
        }
    }
}
```

Do not replace the enum with the snippet as a closed list. Keep all existing cases,
protocol conformances, computed properties, and switch branches, and only add the
Scratchpad case and title branch where they fit the current file.

- [ ] **Step 3: Add the feature title mapping**

In `platforms/macos/Atlas/FeatureModels.swift`, update `AtlasFeatureTitles.title(for:)`:

```swift
private enum AtlasFeatureTitles {
    static func title(for name: String) -> String {
        switch name {
        case AtlasModule.monitoring.featureName:
            return AtlasModule.monitoring.title
        case AtlasModule.scratchpad.featureName:
            return AtlasModule.scratchpad.title
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

- [ ] **Step 4: Add Swift feature title coverage**

In `platforms/macos/AtlasTests/FeatureModelsTests.swift`, add:

```swift
func testMapsScratchpadFeatureTitle() {
    let entry = FeatureEntry(name: "scratchpad", status: .disabled)

    let feature = AtlasFeatureMapper.map(entry)

    XCTAssertEqual(feature, AtlasFeature(name: "scratchpad", isEnabled: false))
    XCTAssertEqual(feature.title, "Scratchpad")
}
```

- [ ] **Step 5: Verify feature registration**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/FeatureModelsTests
```

Expected: Rust feature ordering and Swift title mapping tests pass.

---

### Task 2: Add Markdown Note Models and Store

**Files:**
- Create: `platforms/macos/Atlas/ScratchpadModels.swift`
- Create: `platforms/macos/Atlas/ScratchpadStore.swift`
- Create: `platforms/macos/AtlasTests/ScratchpadStoreTests.swift`

- [ ] **Step 1: Add Scratchpad models**

Create `platforms/macos/Atlas/ScratchpadModels.swift`:

```swift
import Foundation

struct ScratchpadNote: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var markdown: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        markdown: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.markdown = markdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ScratchpadDraft: Equatable {
    var title: String
    var markdown: String

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedMarkdown: String {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !normalizedTitle.isEmpty || !normalizedMarkdown.isEmpty
    }
}

enum ScratchpadStoreError: LocalizedError, Equatable {
    case invalidDraft
    case noteNotFound

    var errorDescription: String? {
        switch self {
        case .invalidDraft:
            return "Scratchpad notes require a title or Markdown body."
        case .noteNotFound:
            return "Scratchpad note was not found."
        }
    }
}
```

- [ ] **Step 2: Add JSON-backed storage**

Create `platforms/macos/Atlas/ScratchpadStore.swift`:

```swift
import Foundation

protocol ScratchpadStoring {
    func loadNotes() throws -> [ScratchpadNote]
    func create(_ draft: ScratchpadDraft) throws -> ScratchpadNote
    func update(id: UUID, draft: ScratchpadDraft) throws -> ScratchpadNote
    func delete(id: UUID) throws
    func search(_ query: String) throws -> [ScratchpadNote]
}

final class ScratchpadStore: ScratchpadStoring {
    private let fileURL: URL
    private let dateProvider: () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL = ScratchpadStore.defaultFileURL(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.dateProvider = dateProvider
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadNotes() throws -> [ScratchpadNote] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([ScratchpadNote].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func create(_ draft: ScratchpadDraft) throws -> ScratchpadNote {
        guard draft.isValid else { throw ScratchpadStoreError.invalidDraft }
        let now = dateProvider()
        let note = ScratchpadNote(
            title: title(for: draft),
            markdown: draft.markdown,
            createdAt: now,
            updatedAt: now
        )
        var notes = try loadNotes()
        notes.insert(note, at: 0)
        try save(notes)
        return note
    }

    func update(id: UUID, draft: ScratchpadDraft) throws -> ScratchpadNote {
        guard draft.isValid else { throw ScratchpadStoreError.invalidDraft }
        var notes = try loadNotes()
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw ScratchpadStoreError.noteNotFound
        }
        let existing = notes[index]
        let updated = ScratchpadNote(
            id: existing.id,
            title: title(for: draft),
            markdown: draft.markdown,
            createdAt: existing.createdAt,
            updatedAt: dateProvider()
        )
        notes[index] = updated
        try save(notes)
        return updated
    }

    func delete(id: UUID) throws {
        var notes = try loadNotes()
        let originalCount = notes.count
        notes.removeAll { $0.id == id }
        guard notes.count != originalCount else {
            throw ScratchpadStoreError.noteNotFound
        }
        try save(notes)
    }

    func search(_ query: String) throws -> [ScratchpadNote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return try loadNotes() }
        return try loadNotes().filter { note in
            note.title.localizedCaseInsensitiveContains(q) ||
                note.markdown.localizedCaseInsensitiveContains(q)
        }
    }

    private func save(_ notes: [ScratchpadNote]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(notes.sorted { $0.updatedAt > $1.updatedAt })
        try data.write(to: fileURL, options: [.atomic])
    }

    private func title(for draft: ScratchpadDraft) -> String {
        if !draft.normalizedTitle.isEmpty {
            return draft.normalizedTitle
        }

        return draft.normalizedMarkdown
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0.prefix(80)) } ?? "Untitled"
    }

    static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("Scratchpad", isDirectory: true)
            .appendingPathComponent("notes.json")
    }
}
```

- [ ] **Step 3: Add store tests**

Create `platforms/macos/AtlasTests/ScratchpadStoreTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScratchpadStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScratchpadStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCreatePersistsMarkdownNote() throws {
        let store = makeStore(date: Date(timeIntervalSince1970: 10))

        let note = try store.create(ScratchpadDraft(title: "Plan", markdown: "# Heading\n- item"))
        let loaded = try makeStore().loadNotes()

        XCTAssertEqual(note.title, "Plan")
        XCTAssertEqual(note.markdown, "# Heading\n- item")
        XCTAssertEqual(loaded, [note])
    }

    func testCreateUsesFirstMarkdownLineWhenTitleIsEmpty() throws {
        let store = makeStore()

        let note = try store.create(ScratchpadDraft(title: "   ", markdown: "First line\nSecond line"))

        XCTAssertEqual(note.title, "First line")
    }

    func testRejectsEmptyDraft() {
        let store = makeStore()

        XCTAssertThrowsError(try store.create(ScratchpadDraft(title: " ", markdown: "\n"))) { error in
            XCTAssertEqual(error as? ScratchpadStoreError, .invalidDraft)
        }
    }

    func testUpdatePreservesCreatedAtAndChangesUpdatedAt() throws {
        let createdAt = Date(timeIntervalSince1970: 10)
        let updatedAt = Date(timeIntervalSince1970: 20)
        let store = makeStore(date: createdAt)
        let note = try store.create(ScratchpadDraft(title: "Draft", markdown: "Old"))

        let updateStore = makeStore(date: updatedAt)
        let updated = try updateStore.update(
            id: note.id,
            draft: ScratchpadDraft(title: "Final", markdown: "New **markdown**")
        )

        XCTAssertEqual(updated.id, note.id)
        XCTAssertEqual(updated.createdAt, createdAt)
        XCTAssertEqual(updated.updatedAt, updatedAt)
        XCTAssertEqual(updated.title, "Final")
        XCTAssertEqual(updated.markdown, "New **markdown**")
    }

    func testDeleteRemovesNote() throws {
        let store = makeStore()
        let note = try store.create(ScratchpadDraft(title: "Delete me", markdown: "body"))

        try store.delete(id: note.id)

        XCTAssertEqual(try store.loadNotes(), [])
    }

    func testSearchMatchesTitleAndMarkdown() throws {
        let store = makeStore()
        _ = try store.create(ScratchpadDraft(title: "Release", markdown: "Ship checklist"))
        _ = try store.create(ScratchpadDraft(title: "Idea", markdown: "Markdown parser notes"))

        XCTAssertEqual(try store.search("release").map(\.title), ["Release"])
        XCTAssertEqual(try store.search("parser").map(\.title), ["Idea"])
    }

    func testInvalidJsonThrowsDecodeError() throws {
        let fileURL = notesURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        XCTAssertThrowsError(try makeStore().loadNotes())
    }

    private func makeStore(date: Date = Date(timeIntervalSince1970: 1)) -> ScratchpadStore {
        ScratchpadStore(fileURL: notesURL(), dateProvider: { date })
    }

    private func notesURL() -> URL {
        tempDirectory.appendingPathComponent("notes.json")
    }
}
```

- [ ] **Step 4: Verify store tests fail before project membership**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/ScratchpadStoreTests
```

Expected before PBX membership: Xcode reports `Skipping tests; no test bundle found matching AtlasTests/ScratchpadStoreTests` or the new test class is not compiled. Continue to Task 6 to add explicit project references before expecting this test command to pass.

---

### Task 3: Add Optional Summary Service

**Files:**
- Create: `platforms/macos/Atlas/ScratchpadSummaryService.swift`
- Create: `platforms/macos/AtlasTests/ScratchpadSummaryServiceTests.swift`

- [ ] **Step 1: Add the injected summarizer protocol and disabled default**

Create `platforms/macos/Atlas/ScratchpadSummaryService.swift`:

```swift
import Foundation

struct ScratchpadSummaryResult: Equatable, Sendable {
    let noteID: UUID
    let summary: String
}

protocol ScratchpadSummarizing {
    func summarize(note: ScratchpadNote) async throws -> ScratchpadSummaryResult?
}

struct DisabledScratchpadSummarizer: ScratchpadSummarizing {
    func summarize(note: ScratchpadNote) async throws -> ScratchpadSummaryResult? {
        nil
    }
}
```

- [ ] **Step 2: Add summary tests**

Create `platforms/macos/AtlasTests/ScratchpadSummaryServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScratchpadSummaryServiceTests: XCTestCase {
    func testDisabledSummarizerReturnsNil() async throws {
        let note = ScratchpadNote(title: "Design", markdown: "# Design\nDetails")
        let summarizer = DisabledScratchpadSummarizer()

        let result = try await summarizer.summarize(note: note)

        XCTAssertNil(result)
    }

    func testInjectedSummarizerCanReturnSummary() async throws {
        let note = ScratchpadNote(title: "Design", markdown: "# Design\nDetails")
        let summarizer = FakeScratchpadSummarizer(summary: "Summarized design details.")

        let result = try await summarizer.summarize(note: note)

        XCTAssertEqual(result, ScratchpadSummaryResult(noteID: note.id, summary: "Summarized design details."))
    }
}

private struct FakeScratchpadSummarizer: ScratchpadSummarizing {
    let summary: String

    func summarize(note: ScratchpadNote) async throws -> ScratchpadSummaryResult? {
        ScratchpadSummaryResult(noteID: note.id, summary: summary)
    }
}
```

- [ ] **Step 3: Verify summary tests after project membership**

Run this after Task 6 adds PBX references:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/ScratchpadSummaryServiceTests
```

Expected: Both summary service tests pass without network or model access.

---

### Task 4: Add Scratchpad Panel

**Files:**
- Create: `platforms/macos/Atlas/ScratchpadPanel.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Add the Scratchpad SwiftUI panel**

Create `platforms/macos/Atlas/ScratchpadPanel.swift`:

```swift
import SwiftUI

struct ScratchpadPanel: View {
    let store: ScratchpadStoring
    let summarizer: ScratchpadSummarizing
    let initialSelectedNoteID: UUID? = nil

    @State private var notes: [ScratchpadNote] = []
    @State private var selectedID: UUID?
    @State private var draft = ScratchpadDraft(title: "", markdown: "")
    @State private var query: String = ""
    @State private var summaryText: String = ""
    @State private var statusText: String = ""
    @State private var isSummarizing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Scratchpad", systemImage: "note.text")
                    .font(.headline)
                Spacer()
                Button {
                    newNote()
                } label: {
                    Label("New", systemImage: "plus")
                }
            }

            TextField("Search notes", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _ in loadNotes() }

            HStack(alignment: .top, spacing: 12) {
                List(notes, selection: $selectedID) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(note.markdown)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .tag(note.id)
                }
                .frame(minWidth: 140, minHeight: 220)
                .onChange(of: selectedID) { _ in selectCurrentNote() }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: $draft.title)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $draft.markdown)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25))
                        )

                    HStack {
                        Button {
                            saveDraft()
                        } label: {
                            Label(selectedID == nil ? "Create" : "Save", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!draft.isValid)

                        Button(role: .destructive) {
                            deleteSelectedNote()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(selectedID == nil)

                        Spacer()

                        Button {
                            summarizeSelectedNote()
                        } label: {
                            Label("Summarize", systemImage: "sparkles")
                        }
                        .disabled(selectedNote == nil || isSummarizing)
                    }
                }
            }

            if !summaryText.isEmpty {
                Text(summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            selectedID = initialSelectedNoteID
            loadNotes()
        }
    }

    private var selectedNote: ScratchpadNote? {
        guard let selectedID else { return nil }
        return notes.first { $0.id == selectedID }
    }

    private func loadNotes() {
        do {
            notes = try store.search(query)
            if let selectedID, !notes.contains(where: { $0.id == selectedID }) {
                self.selectedID = notes.first?.id
            }
            selectCurrentNote()
            statusText = ""
        } catch {
            notes = []
            statusText = error.localizedDescription
        }
    }

    private func selectCurrentNote() {
        guard let selectedNote else { return }
        draft = ScratchpadDraft(title: selectedNote.title, markdown: selectedNote.markdown)
        summaryText = ""
    }

    private func newNote() {
        selectedID = nil
        draft = ScratchpadDraft(title: "", markdown: "")
        summaryText = ""
        statusText = ""
    }

    private func saveDraft() {
        do {
            let saved: ScratchpadNote
            if let selectedID {
                saved = try store.update(id: selectedID, draft: draft)
            } else {
                saved = try store.create(draft)
            }
            selectedID = saved.id
            loadNotes()
            statusText = "Saved"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func deleteSelectedNote() {
        guard let selectedID else { return }
        do {
            try store.delete(id: selectedID)
            self.selectedID = nil
            draft = ScratchpadDraft(title: "", markdown: "")
            summaryText = ""
            loadNotes()
            statusText = "Deleted"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func summarizeSelectedNote() {
        guard let note = selectedNote else { return }
        isSummarizing = true
        summaryText = ""

        Task {
            do {
                if let result = try await summarizer.summarize(note: note) {
                    summaryText = result.summary
                } else {
                    summaryText = "Summary is not configured."
                }
            } catch {
                summaryText = error.localizedDescription
            }
            isSummarizing = false
        }
    }
}
```

- [ ] **Step 2: Show the panel behind Feature Center gating**

In `platforms/macos/Atlas/ContentView.swift`, add stored dependencies near the other stores:

```swift
private let scratchpadStore = ScratchpadStore()
private let scratchpadSummarizer = DisabledScratchpadSummarizer()
```

In `body`, place this block after the monitoring panel and before `FeatureCenterPanel`:

```swift
if isFeatureEnabled(.scratchpad) {
    ScratchpadPanel(
        store: scratchpadStore,
        summarizer: scratchpadSummarizer
    )

    Divider()
}
```

- [ ] **Step 3: Verify the app still builds after project membership**

Run this after Task 6 adds PBX references:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: The app builds and the Scratchpad panel is compiled into the `Atlas` target.

---

### Task 5: Add Command Palette Access

**Files:**
- Create: `platforms/macos/Atlas/CommandPalette/ScratchpadProvider.swift`
- Modify: `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`
- Modify: `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`
- Modify: `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`
- Modify: `platforms/macos/Atlas/AtlasApp.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Create: `platforms/macos/AtlasTests/ScratchpadProviderTests.swift`

- [ ] **Step 1: Add the Scratchpad command provider**

Create `platforms/macos/Atlas/CommandPalette/ScratchpadProvider.swift`:

```swift
import Foundation

final class ScratchpadProvider: CommandProviding {
    private static let maxResultsCount = 5

    private let store: ScratchpadStoring
    private var isEnabled: Bool

    init(store: ScratchpadStoring = ScratchpadStore(), isEnabled: Bool = false) {
        self.store = store
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled else { return [] }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return [
                PaletteCommand(
                    id: UUID(),
                    title: "Open Scratchpad",
                    subtitle: "Create and edit Markdown notes",
                    icon: .sfSymbol("note.text"),
                    keywords: ["scratchpad", "note", "markdown"],
                    action: .push(.scratchpad(noteID: nil)),
                    category: "Scratchpad"
                ),
            ]
        }

        let notes = (try? store.search(q)) ?? []
        return notes
            .prefix(Self.maxResultsCount)
            .map { note in
                PaletteCommand(
                    id: note.id,
                    title: note.title,
                    subtitle: Self.subtitle(for: note.markdown),
                    icon: .sfSymbol("note.text"),
                    keywords: ["scratchpad", "note", "markdown", note.title],
                    action: .push(.scratchpad(noteID: note.id)),
                    category: "Scratchpad"
                )
            }
    }

    private static func subtitle(for markdown: String) -> String {
        let collapsed = markdown
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return String(collapsed.prefix(80))
    }
}
```

- [ ] **Step 2: Add the command palette destination**

In `platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift`, add a
Scratchpad destination that can carry an optional selected note ID:

```swift
enum PaletteDestination: Equatable {
    case scratchpad(noteID: UUID?)
    // Preserve every existing destination case from the file, including cases
    // added by other child plans such as custom automation.
    case windowPicker
    case screenshotLibrary
    case portLookup
}
```

Do not replace the enum with this closed list. Add `scratchpad(noteID:)` alongside
the existing destination cases and keep all adjacent feature destinations intact.
The empty-query "Open Scratchpad" command should push `.scratchpad(noteID: nil)`;
note search results must push `.scratchpad(noteID: note.id)` so selecting a
result opens the matching note.

- [ ] **Step 3: Add a Scratchpad destination builder**

In `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`, add the property:

```swift
var scratchpadViewBuilder: ((UUID?) -> AnyView)?
```

When constructing `CommandPaletteView` in `show()`, pass the new builder
additively:

```swift
let paletteView = CommandPaletteView(
    providers: providers,
    onDismiss: { [weak self] in
        Task { @MainActor [weak self] in
            self?.hide()
        }
    },
    usageRecorder: usageRecorder,
    screenshotLibraryViewBuilder: screenshotLibraryViewBuilder,
    portLookupViewBuilder: portLookupViewBuilder,
    windowPickerViewBuilder: windowPickerViewBuilder,
    // Preserve every existing builder argument already passed here.
    scratchpadViewBuilder: scratchpadViewBuilder
)
```

Do not replace the `CommandPaletteView` initializer call with the snippet as a
closed list. Keep all existing builder arguments from the file, including builders
added by other child plans such as custom automation, and append/pass the
Scratchpad builder in the same style.

- [ ] **Step 4: Render the Scratchpad destination**

In `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`, add the stored builder:

```swift
let scratchpadViewBuilder: ((UUID?) -> AnyView)?
```

Update the initializer signature and assignment additively:

```swift
init(
    providers: [CommandProviding],
    onDismiss: @escaping () -> Void,
    usageRecorder: CommandUsageRecording = CommandUsageStore(),
    screenshotLibraryViewBuilder: (() -> AnyView)? = nil,
    portLookupViewBuilder: (() -> AnyView)? = nil,
    windowPickerViewBuilder: (() -> AnyView)? = nil,
    // Preserve every existing builder parameter already present here.
    scratchpadViewBuilder: ((UUID?) -> AnyView)? = nil
) {
    self.providers = providers
    self.onDismiss = onDismiss
    self.usageRecorder = usageRecorder
    self.screenshotLibraryViewBuilder = screenshotLibraryViewBuilder
    self.portLookupViewBuilder = portLookupViewBuilder
    self.windowPickerViewBuilder = windowPickerViewBuilder
    // Preserve every existing builder assignment already present here.
    self.scratchpadViewBuilder = scratchpadViewBuilder
}
```

Update `subView(for:)`:

```swift
@ViewBuilder
private func subView(for dest: PaletteDestination) -> some View {
    switch dest {
    case .scratchpad(let noteID):
        scratchpadViewBuilder?(noteID) ?? AnyView(Text("Scratchpad").padding())
    // Preserve every existing destination branch already present here.
    case .screenshotLibrary:
        screenshotLibraryViewBuilder?() ?? AnyView(Text("Screenshot Library").padding())
    case .portLookup:
        portLookupViewBuilder?() ?? AnyView(Text("Port Lookup").padding())
    case .windowPicker:
        windowPickerViewBuilder?() ?? AnyView(Text("Window Picker").padding())
    }
}
```

Do not replace `subView(for:)` with this closed switch. Add the Scratchpad branch
and keep every existing branch from the file, including branches added by other
child plans. If Swift exhaustiveness requires reordering, preserve behavior for
all non-Scratchpad destinations.

- [ ] **Step 5: Wire the shared provider in app state**

In `platforms/macos/Atlas/AtlasApp.swift`, update `CommandPaletteState`:

```swift
@MainActor
final class CommandPaletteState: ObservableObject {
    private(set) var controller: CommandPaletteController!
    private let hotkeyService = GlobalHotkeyService()
    private let scratchpadStore = ScratchpadStore()
    private let scratchpadProvider: ScratchpadProvider

    var sharedScratchpadStore: ScratchpadStore {
        scratchpadStore
    }

    init() {
        scratchpadProvider = ScratchpadProvider(store: scratchpadStore)

        let atlasProvider = AtlasCommandProvider(
            onCaptureDesktop: { [weak self] in self?.onCaptureDesktop?() },
            onCaptureArea: { [weak self] in self?.onCaptureArea?() },
            onCaptureWindow: { [weak self] in self?.onCaptureWindow?() },
            onOpenSettings: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        )
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
            scratchpadProvider,
            // Preserve every existing provider already registered here.
            appLauncherProvider,
        ])

        self.controller.onHotkeyChanged = { [weak self] newConfig in
            self?.registerHotkey(newConfig)
        }

        let config = HotkeyConfig.load()
        registerHotkey(config)
        hotkeyService.start()
    }

    func setScratchpadEnabled(_ isEnabled: Bool) {
        scratchpadProvider.setEnabled(isEnabled)
    }
}
```

Do not replace `CommandPaletteState` or its provider list with this snippet as a
closed list. Keep the existing capture callback properties, `setActions`, and
`registerHotkey(_:)` methods that already exist in `CommandPaletteState`; the
snippet above shows the new stored properties, initialization, provider list
insertion, and enablement method. Preserve every existing provider already
registered in the app, including providers added by other child plans such as
custom automation.

- [ ] **Step 6: Use the shared store and update gating from ContentView**

In `platforms/macos/Atlas/ContentView.swift`, replace the standalone `scratchpadStore` property from Task 4 with:

```swift
private var scratchpadStore: ScratchpadStore {
    paletteState?.sharedScratchpadStore ?? ScratchpadStore()
}
private let scratchpadSummarizer = DisabledScratchpadSummarizer()
```

In `startModules()`, after `enabledFeatures = FeatureStateReducer.enabledMap(from: loadedFeatures)`, add:

```swift
paletteState?.setScratchpadEnabled(isFeatureEnabled(.scratchpad))
```

In `refreshFeature(_:, enabled:)`, add this before the monitoring guard:

```swift
if feature == AtlasModule.scratchpad.featureName {
    paletteState?.setScratchpadEnabled(enabled)
}
```

In `startHotkeys()`, after the existing command palette destination builders, add:

```swift
controller.scratchpadViewBuilder = {
    noteID in
    AnyView(
        ScratchpadPanel(
            store: self.scratchpadStore,
            summarizer: self.scratchpadSummarizer,
            initialSelectedNoteID: noteID
        )
    )
}
```

- [ ] **Step 7: Add provider tests**

Create `platforms/macos/AtlasTests/ScratchpadProviderTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScratchpadProviderTests: XCTestCase {
    func testReturnsNoResultsWhenDisabled() throws {
        let store = InMemoryScratchpadStore(notes: [
            ScratchpadNote(title: "Release", markdown: "Ship checklist"),
        ])
        let provider = ScratchpadProvider(store: store, isEnabled: false)

        XCTAssertEqual(provider.results(for: "release").count, 0)
    }

    func testReturnsOpenCommandForEmptyQueryWhenEnabled() {
        let provider = ScratchpadProvider(store: InMemoryScratchpadStore(), isEnabled: true)

        let results = provider.results(for: " ")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Open Scratchpad")
        XCTAssertEqual(results[0].category, "Scratchpad")
        XCTAssertEqual(results[0].action, .push(.scratchpad(noteID: nil)))
    }

    func testSearchesNotesWhenEnabled() throws {
        let matching = ScratchpadNote(title: "Release", markdown: "Ship checklist")
        let other = ScratchpadNote(title: "Ideas", markdown: "Later")
        let provider = ScratchpadProvider(
            store: InMemoryScratchpadStore(notes: [matching, other]),
            isEnabled: true
        )

        let results = provider.results(for: "ship")

        XCTAssertEqual(results.map(\.title), ["Release"])
        XCTAssertEqual(results.first?.category, "Scratchpad")
        XCTAssertEqual(results.first?.action, .push(.scratchpad(noteID: matching.id)))
    }

    func testSetEnabledAllowsResults() {
        let provider = ScratchpadProvider(
            store: InMemoryScratchpadStore(notes: [
                ScratchpadNote(title: "Daily", markdown: "Notes"),
            ]),
            isEnabled: false
        )

        provider.setEnabled(true)

        XCTAssertEqual(provider.results(for: "daily").map(\.title), ["Daily"])
    }
}

private final class InMemoryScratchpadStore: ScratchpadStoring {
    private var notes: [ScratchpadNote]

    init(notes: [ScratchpadNote] = []) {
        self.notes = notes
    }

    func loadNotes() throws -> [ScratchpadNote] {
        notes
    }

    func create(_ draft: ScratchpadDraft) throws -> ScratchpadNote {
        let note = ScratchpadNote(title: draft.normalizedTitle, markdown: draft.markdown)
        notes.insert(note, at: 0)
        return note
    }

    func update(id: UUID, draft: ScratchpadDraft) throws -> ScratchpadNote {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw ScratchpadStoreError.noteNotFound
        }
        let updated = ScratchpadNote(
            id: id,
            title: draft.normalizedTitle,
            markdown: draft.markdown,
            createdAt: notes[index].createdAt,
            updatedAt: Date()
        )
        notes[index] = updated
        return updated
    }

    func delete(id: UUID) throws {
        notes.removeAll { $0.id == id }
    }

    func search(_ query: String) throws -> [ScratchpadNote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
                $0.markdown.localizedCaseInsensitiveContains(q)
        }
    }
}
```

---

### Task 6: Add Xcode Project Membership

**Files:**
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add app files to the Atlas target**

Add these files to the `Atlas` group and `Atlas` target sources in `platforms/macos/Atlas.xcodeproj/project.pbxproj`:

```text
platforms/macos/Atlas/ScratchpadModels.swift
platforms/macos/Atlas/ScratchpadStore.swift
platforms/macos/Atlas/ScratchpadSummaryService.swift
platforms/macos/Atlas/ScratchpadPanel.swift
platforms/macos/Atlas/CommandPalette/ScratchpadProvider.swift
```

Expected project diff shape:

```diff
+ /* ScratchpadModels.swift in Sources */
+ /* ScratchpadStore.swift in Sources */
+ /* ScratchpadSummaryService.swift in Sources */
+ /* ScratchpadPanel.swift in Sources */
+ /* ScratchpadProvider.swift in Sources */
+ /* ScratchpadModels.swift */
+ /* ScratchpadStore.swift */
+ /* ScratchpadSummaryService.swift */
+ /* ScratchpadPanel.swift */
+ /* ScratchpadProvider.swift */
```

- [ ] **Step 2: Add test files to the AtlasTests target**

Add these files to the `AtlasTests` group and `AtlasTests` target sources in `platforms/macos/Atlas.xcodeproj/project.pbxproj`:

```text
platforms/macos/AtlasTests/ScratchpadStoreTests.swift
platforms/macos/AtlasTests/ScratchpadProviderTests.swift
platforms/macos/AtlasTests/ScratchpadSummaryServiceTests.swift
```

Expected project diff shape:

```diff
+ /* ScratchpadStoreTests.swift in Sources */
+ /* ScratchpadProviderTests.swift in Sources */
+ /* ScratchpadSummaryServiceTests.swift in Sources */
+ /* ScratchpadStoreTests.swift */
+ /* ScratchpadProviderTests.swift */
+ /* ScratchpadSummaryServiceTests.swift */
```

- [ ] **Step 3: Verify project membership**

Run:

```bash
rg -n 'ScratchpadModels|ScratchpadStore|ScratchpadSummaryService|ScratchpadPanel|ScratchpadProvider|ScratchpadStoreTests|ScratchpadProviderTests|ScratchpadSummaryServiceTests' platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: Each new Swift file appears as a file reference and as a source build file. App files appear in the `Atlas` sources build phase; test files appear in the `AtlasTests` sources build phase.

---

### Task 7: Run Verification and Commit

**Files:**
- Verify: `crates/atlas-core/src/features.rs`
- Verify: `platforms/macos/Atlas/**/*.swift`
- Verify: `platforms/macos/AtlasTests/**/*.swift`
- Verify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Run focused Rust feature test**

Run:

```bash
cargo test -p atlas-core test_list_features_is_sorted_by_name
```

Expected: The test passes with the sorted feature list including `scratchpad`.

- [ ] **Step 2: Run focused XCTest slices**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas \
  -only-testing:AtlasTests/FeatureModelsTests \
  -only-testing:AtlasTests/ScratchpadStoreTests \
  -only-testing:AtlasTests/ScratchpadProviderTests \
  -only-testing:AtlasTests/ScratchpadSummaryServiceTests
```

Expected: Feature model, storage, provider, and summary tests pass.

- [ ] **Step 3: Run app build**

Run:

```bash
xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas
```

Expected: The app builds with Scratchpad files included in the explicit Xcode project.

- [ ] **Step 4: Inspect diff**

Run:

```bash
git diff -- crates/atlas-core/src/features.rs platforms/macos/Atlas platforms/macos/AtlasTests platforms/macos/Atlas.xcodeproj/project.pbxproj
```

Expected: The diff contains only Scratchpad feature registration, Scratchpad Swift files, command palette wiring, tests, and explicit Xcode project membership.

- [ ] **Step 5: Commit implementation**

Run:

```bash
git add crates/atlas-core/src/features.rs \
  platforms/macos/Atlas/AtlasModule.swift \
  platforms/macos/Atlas/FeatureModels.swift \
  platforms/macos/Atlas/ContentView.swift \
  platforms/macos/Atlas/AtlasApp.swift \
  platforms/macos/Atlas/CommandPalette/CommandPaletteModels.swift \
  platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift \
  platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift \
  platforms/macos/Atlas/CommandPalette/ScratchpadProvider.swift \
  platforms/macos/Atlas/ScratchpadModels.swift \
  platforms/macos/Atlas/ScratchpadStore.swift \
  platforms/macos/Atlas/ScratchpadSummaryService.swift \
  platforms/macos/Atlas/ScratchpadPanel.swift \
  platforms/macos/AtlasTests/FeatureModelsTests.swift \
  platforms/macos/AtlasTests/ScratchpadStoreTests.swift \
  platforms/macos/AtlasTests/ScratchpadProviderTests.swift \
  platforms/macos/AtlasTests/ScratchpadSummaryServiceTests.swift \
  platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: add Atlas scratchpad"
```

Expected: The commit contains only the Scratchpad implementation and tests.

---

## Self-Review

1. **Spec coverage:** Markdown storage is covered by Task 2; create/edit/delete by Tasks 2 and 4; command palette access by Task 5; optional AI summary by Task 3 and Task 4; Feature Center gating by Tasks 1, 4, and 5; XCTest coverage by Tasks 1, 2, 3, and 5; Xcode project membership by Task 6.
2. **Placeholder scan:** This plan avoids placeholder instructions and provides concrete file paths, code snippets, commands, and expected results.
3. **Type consistency:** `ScratchpadNote`, `ScratchpadDraft`, `ScratchpadStoring`, `ScratchpadSummarizing`, `ScratchpadProvider`, and `PaletteDestination.scratchpad(noteID:)` are defined before later tasks reference them.
