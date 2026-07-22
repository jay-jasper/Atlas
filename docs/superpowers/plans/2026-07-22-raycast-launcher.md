# Raycast Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the old CommandPalette view layer with a new `Launcher/` module that fully replicates the Raycast launcher (minus plugins): navigation stack, sectioned root search, ⌘K action panel, favorites/recents, aliases, per-command hotkeys, quicklinks, fallback search, inline arguments, answer cards, grid view, detail pane, menu-bar item search, and a fully customizable panel style.

**Architecture:** New SwiftUI view layer + interaction model in `platforms/macos/Atlas/Launcher/`. All 44 existing `CommandProviding` providers are reused unchanged through `CommandProviderAdapter`. `CommandPaletteRanker`, `CommandUsageStore`, `GlobalHotkeyService`, `HotkeyConfig` are reused directly. Old `CommandPaletteView.swift` + `CommandPaletteController.swift` are deleted at the end of Phase 1.

**Tech Stack:** SwiftUI (macOS 13+, `onKeyPressCompatible` shim already exists), AppKit `NSPanel`, UserDefaults JSON persistence, XCTest via `xcodebuild`, `xcodeproj` ruby gem for project file registration.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-22-raycast-launcher-design.md`
- List rows must NOT get default focus ring / preselection appearance (`.focusable(false)`) — user hard rule.
- Old palette **providers, models, ranker, usage store, and their tests stay** — only the view layer (`CommandPaletteView.swift`, `CommandPaletteController.swift`) is deleted.
- Project file is objectVersion 56 (explicit file refs): every new file must be registered via `platforms/macos/tools/add_launcher_files.rb` (Task 1 creates it).
- Item stable key format matches `CommandUsageStore.commandKey`: `"\(category)|\(title)"`.
- Tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -only-testing:AtlasTests/<Class> -destination 'platform=macOS'`.
- Commit after every task.

## File Structure

```
platforms/macos/Atlas/Launcher/
├── LauncherModels.swift            # LauncherItem, LauncherAction, LauncherActionOutcome,
│                                   #   LauncherPage, LauncherSection, LauncherDetail,
│                                   #   LauncherQueryParser
├── LauncherItemSource.swift        # source protocol + CommandProviderAdapter
├── LauncherSectionBuilder.swift    # pure function: query + stores → [LauncherSectionData]
├── LauncherNavigationModel.swift   # page stack
├── LauncherStyle.swift             # style model + Codable + per-theme defaults
├── LauncherStyleStore.swift        # persistence (UserDefaults JSON, bad-value fallback)
├── FavoritesStore.swift            # pinned command keys
├── AliasStore.swift                # commandKey → alias
├── CommandHotkeyStore.swift        # commandKey → HotkeyConfig
├── QuicklinkStore.swift            # quicklinks CRUD ({query} templates)
├── FallbackStore.swift             # fallback command ordering/enabled
├── MenuBarItemSource.swift         # AX menu-bar item search (permission-guarded)
├── LauncherPanelController.swift   # NSPanel host (replaces CommandPaletteController)
├── LauncherRootView.swift          # search field + sections + answer card + footer
├── LauncherRowViews.swift          # result row, answer card, section header
├── ActionPanelView.swift           # ⌘K overlay
├── LauncherPageViews.swift         # list/grid/detail/legacy page rendering
└── LauncherStyleSettingsView.swift # style customization UI + live preview
platforms/macos/AtlasTests/
├── LauncherModelsTests.swift
├── LauncherAdapterTests.swift
├── LauncherSectionBuilderTests.swift
├── LauncherNavigationModelTests.swift
├── LauncherStyleTests.swift
└── LauncherStoresTests.swift       # favorites/alias/hotkey/quicklink/fallback stores
platforms/macos/tools/add_launcher_files.rb
```

Modify: `AtlasApp.swift` (route `CommandPaletteState` to new controller), `AtlasSettingsView.swift` (launcher style settings entry).
Delete (end of Phase 1): `CommandPalette/CommandPaletteView.swift`, `CommandPalette/CommandPaletteController.swift`.

---

### Task 1: Core models + query parser + project registration script

**Files:**
- Create: `platforms/macos/Atlas/Launcher/LauncherModels.swift`
- Create: `platforms/macos/tools/add_launcher_files.rb`
- Test: `platforms/macos/AtlasTests/LauncherModelsTests.swift`

**Produces (later tasks rely on):**

```swift
struct LauncherAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let shortcutHint: String?          // display-only, e.g. "⌘C"
    let perform: () -> LauncherActionOutcome
}

enum LauncherActionOutcome { case dismiss, stay, push(LauncherPage) }

enum LauncherSection: Hashable {
    case answer, favorites, recents, results(String), fallback
}

struct LauncherDetail {
    struct Row: Identifiable { let id = UUID(); let label: String; let value: String }
    let rows: [Row]
    let previewText: String?
    let previewImagePath: String?
    static func forFile(path: String) -> LauncherDetail?   // nil when file missing
}

enum LauncherPage {
    case list(title: String, items: () -> [LauncherItem])
    case grid(title: String, columns: Int, items: () -> [LauncherItem])
    case detail(title: String, detail: LauncherDetail)
    case legacy(PaletteDestination)    // bridge to existing sub-views
}

struct LauncherItem: Identifiable {
    let id: String                     // "\(category)|\(title)"
    let title: String
    let subtitle: String?
    let icon: PaletteIcon
    let keywords: [String]
    let category: String
    var actions: [LauncherAction]      // [0] is the primary (↵) action
    var detail: LauncherDetail?
    var isAnswer: Bool                 // renders as answer card at top
    var acceptsArgument: Bool          // consumes query remainder (quicklinks/fallback)
}

enum LauncherQueryParser {
    // "gh swift charts" → (head: "gh", remainder: "swift charts")
    static func split(_ query: String) -> (head: String, remainder: String)
}
```

**Steps:**

- [ ] **Step 1: Write `LauncherModels.swift`** with the exact types above. `LauncherDetail.forFile` uses `FileManager.default.attributesOfItem` to build rows: Name, Path, Size (ByteCountFormatter), Modified (medium date style); returns `nil` when the file does not exist. `LauncherQueryParser.split` trims whitespace, splits on first space.
- [ ] **Step 2: Write failing tests** `LauncherModelsTests`: `testQueryParserSplitsHeadAndRemainder`, `testQueryParserNoRemainder`, `testFileDetailNilForMissingPath`, `testFileDetailRowsForTempFile` (create temp file, assert 4 rows).
- [ ] **Step 3: Write `add_launcher_files.rb`** modeled on `configure_ui_tests.rb`: opens project, ensures group `Atlas/Launcher`, adds every `Launcher/*.swift` to the `Atlas` target and every `AtlasTests/Launcher*Tests.swift` to the `AtlasTests` target, idempotent. Run it.
- [ ] **Step 4: Run tests** → PASS. **Step 5: Commit** `feat(launcher): core models, query parser, project registration script`

### Task 2: CommandProviderAdapter

**Files:**
- Create: `platforms/macos/Atlas/Launcher/LauncherItemSource.swift`
- Test: `platforms/macos/AtlasTests/LauncherAdapterTests.swift`

**Interfaces:**

```swift
protocol LauncherItemSource {
    var sourceID: String { get }
    func items(for query: String) -> [LauncherItem]
}

// Optional enrichment providers can adopt later:
protocol LauncherActionEnriching { func extraActions(for command: PaletteCommand) -> [LauncherAction] }

struct CommandProviderAdapter: LauncherItemSource {
    init(provider: CommandProviding, sourceID: String,
         onLegacyPush: @escaping (PaletteDestination) -> LauncherPage = { .legacy($0) })
}
```

Mapping rules:
- `PaletteCommand.action == .execute(fn)` → primary action `LauncherAction(id: "run", title: "Run", systemImage: "return", shortcutHint: "↵") { fn(); return .dismiss }` plus secondary `"Copy Title"` (`⌘C`, copies `title` to pasteboard, `.dismiss`).
- `.push(dest)` → primary action returns `.push(.legacy(dest))`.
- `category == "Calculator"` or `"Conversion"` → `isAnswer = true`, extra action "Copy Answer" copying `subtitle ?? title`.
- `category == "Files"` → `detail = LauncherDetail.forFile(path: subtitle ?? "")`, extra actions: "Open" (primary), "Reveal in Finder" (`⌘F`, `NSWorkspace.shared.activateFileViewerSelecting`), "Copy Path" (`⌘P`).
- Adapter catches nothing (providers don't throw) but wraps `items(for:)` so an empty array from one source can't affect others (section builder handles isolation).

**Steps:**

- [ ] **Step 1: Failing tests** `LauncherAdapterTests` with a stub `CommandProviding` returning fixed `PaletteCommand`s: `testExecuteCommandMapsToPrimaryRunAction`, `testPushCommandMapsToLegacyPage`, `testCalculatorMarkedAsAnswer`, `testFileCommandGetsDetailAndActions`, `testIDMatchesUsageStoreKey`.
- [ ] **Step 2: Implement adapter.** **Step 3: Register files, run tests** → PASS. **Step 4: Commit** `feat(launcher): command provider adapter`

### Task 3: LauncherStyle + LauncherStyleStore

**Files:**
- Create: `platforms/macos/Atlas/Launcher/LauncherStyle.swift`, `platforms/macos/Atlas/Launcher/LauncherStyleStore.swift`
- Test: `platforms/macos/AtlasTests/LauncherStyleTests.swift`

**Interfaces:**

```swift
struct RGBAColor: Codable, Equatable { var r, g, b, a: Double; var color: Color; var nsColor: NSColor }

struct LauncherStyle: Codable, Equatable {
    enum Background: Codable, Equatable {
        case material(opacity: Double)          // ultraThinMaterial under opacity layer
        case solid(RGBAColor)
        case gradient(RGBAColor, RGBAColor, angleDegrees: Double)
    }
    enum RowDensity: String, Codable { case compact, regular }  // row heights 40 / 52
    var background: Background
    var borderColor: RGBAColor
    var borderWidth: Double            // 0…4
    var cornerRadius: Double           // 0…28
    var panelWidth: Double             // 480…960
    var maxVisibleRows: Int            // 4…12
    var topOffsetRatio: Double         // 0.0 (top) … 0.5 (center); default 0.2
    var rowDensity: RowDensity
    var fontSize: Double               // 13…20, search field = fontSize + 3
    var iconSize: Double               // 24…40
    var accent: RGBAColor?             // nil → theme accent
    static let `default` = LauncherStyle(...)   // material(0.85), radius 16, width 680, 8 rows, 0.2, regular, 15, 32, accent nil, border clear/0
    var rowHeight: CGFloat { rowDensity == .compact ? 40 : 52 }
}

@MainActor final class LauncherStyleStore: ObservableObject {
    @Published var style: LauncherStyle          // didSet → save
    init(defaults: UserDefaults = .standard)     // load "launcher.style" JSON; decode failure → .default
    func reset()
}
```

**Steps:**

- [ ] **Step 1: Failing tests** `LauncherStyleTests`: `testCodableRoundTripAllBackgrounds`, `testDecodeGarbageFallsBackToDefault` (store with suite-name defaults preloaded with `Data("junk".utf8)`), `testStorePersistsAcrossInstances`, `testResetRestoresDefault`.
- [ ] **Step 2: Implement.** Background enum Codable via explicit `CodingKeys` + `case` discriminator. **Step 3: Register, run tests** → PASS. **Step 4: Commit** `feat(launcher): customizable style model and store`

### Task 4: Navigation model

**Files:**
- Create: `platforms/macos/Atlas/Launcher/LauncherNavigationModel.swift`
- Test: `platforms/macos/AtlasTests/LauncherNavigationModelTests.swift`

**Interfaces:**

```swift
@MainActor final class LauncherNavigationModel: ObservableObject {
    @Published private(set) var stack: [LauncherPage] = []
    @Published var query: String = ""
    @Published var selectedIndex: Int = 0
    @Published var isActionPanelOpen: Bool = false
    var currentPage: LauncherPage? { stack.last }
    func push(_ page: LauncherPage)      // clears query + selection
    /// returns false when stack was empty (caller should dismiss panel)
    @discardableResult func popOrSignalDismiss() -> Bool
    func resetToRoot()
}
```

Rules: `push` appends, sets `query = ""`, `selectedIndex = 0`, closes action panel. `popOrSignalDismiss`: action panel open → close it, return true; stack non-empty → pop, return true; else return false.

**Steps:**

- [ ] **Step 1: Failing tests** `LauncherNavigationModelTests`: `testPushClearsQueryAndSelection`, `testPopReturnsTrueWhenStackNonEmpty`, `testPopClosesActionPanelFirst`, `testPopReturnsFalseAtRoot`, `testResetToRoot`.
- [ ] **Step 2: Implement. Step 3: Run tests** → PASS. **Step 4: Commit** `feat(launcher): navigation model`

### Task 5: Section builder (+ favorites/recents stores it needs)

**Files:**
- Create: `platforms/macos/Atlas/Launcher/FavoritesStore.swift`, `platforms/macos/Atlas/Launcher/LauncherSectionBuilder.swift`
- Test: `platforms/macos/AtlasTests/LauncherStoresTests.swift` (favorites part), `platforms/macos/AtlasTests/LauncherSectionBuilderTests.swift`

**Interfaces:**

```swift
@MainActor final class FavoritesStore: ObservableObject {
    @Published private(set) var pinnedKeys: [String]      // ordered
    init(defaults: UserDefaults = .standard)              // key "launcher.favorites"
    func isPinned(_ key: String) -> Bool
    func toggle(_ key: String)
    func move(fromOffsets: IndexSet, toOffset: Int)
}

struct LauncherSectionData: Identifiable {
    let id: LauncherSection
    let title: String        // "Favorites" / "Recents" / category / "Use with…"
    let items: [LauncherItem]
}

enum LauncherSectionBuilder {
    static func build(
        query: String,
        sources: [LauncherItemSource],
        favorites: [String],                       // pinned keys, ordered
        records: [String: CommandUsageRecord],
        fallbackItems: [LauncherItem],             // from Task 9; pass [] until then
        recentsLimit: Int = 5
    ) -> [LauncherSectionData]
}
```

Rules (Raycast order):
1. Collect `allItems = sources.flatMap { $0.items(for: query) }`; a source that returns `[]` contributes nothing (isolation).
2. `answer` section: items with `isAnswer`, first only.
3. Empty query: `favorites` section (pinned keys resolved against `sources.flatMap { $0.items(for: "") }`, preserving pin order), then `recents` (top `recentsLimit` by `executionCount`/`lastExecutedAt` from records, excluding pinned), then per-category `results` sections ranked by `CommandPaletteRanker`.
4. Non-empty query: answer, then matching results grouped by category (rank inside category), pinned items float to a leading `favorites` section when they match.
5. `fallback` section appended always when `fallbackItems` non-empty AND query non-empty; titled "Use \"<query>\" with…".
6. Deduplicate by item id across sections (first section wins).

**Steps:**

- [ ] **Step 1: Failing tests.** Favorites: `testTogglePinsAndUnpins`, `testPersistsOrder`. Builder (stub sources): `testEmptyQueryShowsFavoritesThenRecentsThenCategories`, `testAnswerItemFirst`, `testFallbackAppendedForNonEmptyQuery`, `testNoFallbackOnEmptyQuery`, `testDedupeAcrossSections`, `testEmptySourceIsolated`.
- [ ] **Step 2: Implement. Step 3: Run tests** → PASS. **Step 4: Commit** `feat(launcher): favorites store and section builder`

### Task 6: Panel + root view + footer + ⌘K action panel + page views (UI shell)

**Files:**
- Create: `LauncherPanelController.swift`, `LauncherRootView.swift`, `LauncherRowViews.swift`, `ActionPanelView.swift`, `LauncherPageViews.swift` (all under `Launcher/`)

**Interfaces:**

```swift
@MainActor final class LauncherPanelController {
    init(sources: [LauncherItemSource],
         usageRecorder: CommandUsageRecording,
         styleStore: LauncherStyleStore,
         favorites: FavoritesStore,
         legacyViewBuilder: @escaping (PaletteDestination) -> AnyView)
    func toggle(); func show(); func hide()
    var onHotkeyChanged: ((HotkeyConfig) -> Void)?
    func updateHotkey(_ config: HotkeyConfig)
}
```

Behavior (ports `CommandPaletteController` NSPanel mechanics — borderless nonactivating panel, `.modalPanel` level, all-spaces, global click-outside monitor — then applies `styleStore.style`): panel width `style.panelWidth`, height `52 + rows*rowHeight + 40` (search + list + footer), position `topOffsetRatio`.

`LauncherRootView` layout top→bottom: search field (font `style.fontSize + 3`, placeholder "Search Atlas…"), section list (`ScrollViewReader`, flattened `[(section, item)]` array for index navigation, headers = section title caps caption), footer bar (left: selected item icon+title; right: primary action title + "↵" and "Actions ⌘K" button). Answer card renders as prominent rounded card above sections. Every row `.focusable(false)`, selection = accent-tinted rounded rect (accent from `style.accent ?? theme`).

Key handling (reuse `onKeyPressCompatible`, add `⌘K` via `NSEvent.addLocalMonitorForEvents` in panel controller):
- ↑/↓ + ⌃P/⌃N move selection; ↵ primary action; ⌘↵ second action; ⌘K toggles `ActionPanelView`; Esc → `popOrSignalDismiss()` else `hide()`; typing routes to search field (field stays first responder).
- Action outcome handling: `.dismiss` → record usage + hide; `.push(page)` → record usage + `nav.push(page)`; `.stay` → record usage only.

`ActionPanelView`: bottom-right anchored overlay listing `selectedItem.actions` with shortcut hints, filter field, ↑↓/↵ inside panel, Esc closes.

`LauncherPageViews`: renders `LauncherPage` — `.list` reuses row views with local filtering by `nav.query`; `.grid` = `LazyVGrid` with `columns`, arrow-key navigation left/right/up/down; `.detail` = split: rows table + preview; `.legacy(dest)` = `legacyViewBuilder(dest)`.

**Steps:**

- [ ] **Step 1: Implement all five files.** Style application: background switch (material → `.ultraThinMaterial` + white/black overlay opacity; solid/gradient → fill), `RoundedRectangle(cornerRadius: style.cornerRadius)` clip, overlay stroke `borderColor`/`borderWidth`.
- [ ] **Step 2: Register files; build** `xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug` → succeeds.
- [ ] **Step 3: Commit** `feat(launcher): panel shell, root view, action panel, page views`

### Task 7: Wire into app, delete old view layer

**Files:**
- Modify: `platforms/macos/Atlas/AtlasApp.swift` (`CommandPaletteState`), `platforms/macos/Atlas/AtlasSettingsView.swift`
- Delete: `platforms/macos/Atlas/CommandPalette/CommandPaletteView.swift`, `platforms/macos/Atlas/CommandPalette/CommandPaletteController.swift`

**Steps:**

- [ ] **Step 1:** In `CommandPaletteState`: build `sources = providers.map { CommandProviderAdapter(provider: $0, sourceID: String(describing: type(of: $0))) }`; replace `CommandPaletteController` with `LauncherPanelController(sources:usageRecorder:styleStore:favorites:legacyViewBuilder:)`. `legacyViewBuilder` switch reproduces old `subView(for:)` closure-builder dispatch (screenshotLibrary…skillRun) — move the builder properties onto `LauncherPanelController` unchanged. Keep `onHotkeyChanged`/`updateHotkey` contract so `AtlasSettingsView` hotkey recorder keeps working (rename references from `controller` type only).
- [ ] **Step 2:** Delete the two old files, remove their pbxproj references via `add_launcher_files.rb` (extend script with a `REMOVED_FILES` list), keep `KeyRecorderView.swift` (holds `HotkeyConfig`) and `AutomationOutputView.swift` (used by legacy page).
- [ ] **Step 3:** Build + run full `AtlasTests` → PASS (existing ranker/store/provider tests untouched).
- [ ] **Step 4: Commit** `feat(launcher)!: replace command palette with raycast-style launcher`

### Task 8: Alias store + per-command hotkeys

**Files:**
- Create: `Launcher/AliasStore.swift`, `Launcher/CommandHotkeyStore.swift`
- Modify: `LauncherSectionBuilder.swift` (alias matching), `LauncherPanelController.swift` (hotkey registration), `AtlasApp.swift` (pass stores)
- Test: extend `LauncherStoresTests.swift`, `LauncherSectionBuilderTests.swift`

**Interfaces:**

```swift
@MainActor final class AliasStore: ObservableObject {
    @Published private(set) var aliases: [String: String]   // commandKey → alias
    func alias(for key: String) -> String?
    func setAlias(_ alias: String?, for key: String)        // nil/empty removes; alias lowercased, unique (last write wins)
    func commandKey(matching query: String) -> String?      // exact or prefix match on alias
}

@MainActor final class CommandHotkeyStore: ObservableObject {
    @Published private(set) var hotkeys: [String: HotkeyConfig]  // commandKey → hotkey
    func set(_ config: HotkeyConfig?, for key: String)
}
```

Builder change: `build(...)` gains `aliases: AliasStore?` param; when `aliases.commandKey(matching: query)` hits, resolve that item from `sources` with empty query and prepend it to results (before answer dedupe). Panel controller: on init and on `hotkeys` change, register each config with `GlobalHotkeyService` → handler shows panel? No — Raycast per-command hotkey executes directly: resolve item by key from sources (empty query) and run primary action without opening the panel; `.push` outcomes open the panel on that page.

**Steps:**

- [ ] **Step 1: Failing tests:** `testAliasSetAndRemove`, `testAliasPrefixMatch`, `testAliasPersists`, `testHotkeyStorePersists`, builder: `testAliasMatchPrependsItem`.
- [ ] **Step 2: Implement stores + builder change + controller registration.** Registration failures (conflict) surface via `@Published var registrationErrors: [String: String]` on the controller for the settings UI.
- [ ] **Step 3: Run tests + build** → PASS. **Step 4: Commit** `feat(launcher): aliases and per-command hotkeys`

### Task 9: Quicklinks + fallback search + inline arguments

**Files:**
- Create: `Launcher/QuicklinkStore.swift`, `Launcher/FallbackStore.swift`
- Modify: `LauncherSectionBuilder.swift`, `AtlasApp.swift` (wire sources)
- Test: extend `LauncherStoresTests.swift`, `LauncherSectionBuilderTests.swift`

**Interfaces:**

```swift
struct Quicklink: Codable, Equatable, Identifiable {
    var id: UUID; var name: String; var template: String     // may contain {query}
    func resolvedURL(argument: String?) -> URL?              // {query} percent-encoded; nil arg + {query} present → nil
}
@MainActor final class QuicklinkStore: ObservableObject {    // key "launcher.quicklinks"
    @Published private(set) var quicklinks: [Quicklink]
    func add(_ q: Quicklink); func update(_ q: Quicklink); func remove(id: UUID)
    func makeItems(query: String) -> [LauncherItem]          // name-matching → item; template w/ {query} → acceptsArgument
}
struct FallbackCommand: Codable, Equatable, Identifiable {
    var id: String; var name: String; var template: String; var enabled: Bool
    static let defaults: [FallbackCommand]   // Google, DuckDuckGo, "Search Files"
}
@MainActor final class FallbackStore: ObservableObject {     // key "launcher.fallbacks"
    @Published private(set) var commands: [FallbackCommand]
    func move(fromOffsets: IndexSet, toOffset: Int); func setEnabled(_: Bool, id: String)
    func makeItems(query: String) -> [LauncherItem]          // enabled only, in order; primary action opens resolved URL, .dismiss
}
```

Inline arguments: for items with `acceptsArgument`, section builder resolves via `LauncherQueryParser.split(query)` — head matches the item name/alias, remainder becomes the argument (footer shows "Open with \"<remainder>\""). Quicklink/fallback primary actions receive the argument through closure capture at build time (builder passes `remainder` into `makeItems`).

**Steps:**

- [ ] **Step 1: Failing tests:** quicklink `testResolvedURLEncodesQuery`, `testResolvedURLNilWithoutRequiredArgument`, `testCRUDPersists`; fallback `testDefaultsSeeded`, `testReorderPersists`, `testDisabledExcluded`; builder `testQuicklinkHeadPlusArgument`, `testFallbackReceivesFullQuery`.
- [ ] **Step 2: Implement; wire `quicklinkStore.makeItems` + `fallbackStore.makeItems` into `CommandPaletteState` section building.**
- [ ] **Step 3: Run tests + build** → PASS. **Step 4: Commit** `feat(launcher): quicklinks, fallback search, inline arguments`

### Task 10: Grid emoji page + detail pane polish

**Files:**
- Modify: `Launcher/LauncherItemSource.swift` (EmojiProvider → grid page), `Launcher/LauncherPageViews.swift`, `Launcher/LauncherRootView.swift`
- Test: extend `LauncherAdapterTests.swift`

**Steps:**

- [ ] **Step 1:** Adapter special-case: source whose provider is `EmojiProvider` and query empty-prefixed "emoji" exposes a root item "Search Emoji" whose primary action is `.push(.grid(title: "Emoji", columns: 8, items: { adapter items for "" }))`. Grid cells render emoji glyph large (title first char) + tooltip name; ↵ copies to pasteboard (existing provider action) and dismisses.
- [ ] **Step 2:** Detail pane: when `selectedItem.detail != nil` render right-hand split (fixed 260pt) in root list: metadata rows + preview text/image. Clipboard history items: adapter maps category "Clipboard" text into `LauncherDetail(previewText:)`.
- [ ] **Step 3: Test:** `testEmojiRootItemPushesGridPage`, `testClipboardItemGetsPreviewDetail`. Run tests + build → PASS.
- [ ] **Step 4: Commit** `feat(launcher): emoji grid page and detail pane`

### Task 11: Style settings UI

**Files:**
- Create: `Launcher/LauncherStyleSettingsView.swift`
- Modify: `AtlasSettingsView.swift` (add "启动台" section/tab entry), `AtlasApp.swift` (inject stores)

**Steps:**

- [ ] **Step 1: Implement settings view:** background picker (Material/Solid/Gradient + ColorPickers + opacity slider), border color/width, corner radius slider, panel width slider, visible rows stepper, position slider (top offset), row density picker, font/icon size sliders, accent color override toggle, Reset button. Right side: live miniature preview (a scaled `LauncherRootView` mock with 3 static rows) driven by the same `LauncherStyleStore`. Also: fallback command reorder list, quicklink CRUD table, alias/hotkey editor (list of known commands from sources with alias text field + `KeyRecorderView`, conflict errors from `registrationErrors` shown red).
- [ ] **Step 2: Build + manual smoke** (launch app, open settings). **Step 3: Commit** `feat(launcher): style customization settings with live preview`

### Task 12: Menu-bar item search

**Files:**
- Create: `Launcher/MenuBarItemSource.swift`
- Modify: `AtlasApp.swift` (append source)
- Test: `platforms/macos/AtlasTests/LauncherMenuBarTests.swift`

**Interfaces:**

```swift
protocol MenuBarReading { func frontmostAppMenuItems() -> [MenuBarEntry] }
struct MenuBarEntry: Equatable { let path: [String]; let element: AXUIElement? }
final class AXMenuBarReader: MenuBarReading { }   // walks AXMenuBar of frontmost app, depth ≤ 3, skips Apple menu

@MainActor final class MenuBarItemSource: LauncherItemSource {
    init(reader: MenuBarReading = AXMenuBarReader(),
         isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() })
    // query "menu <text>" or prefix "sm " → menu items; without permission returns single
    // "Search Menu Items — Grant Accessibility Access" item whose action opens System Settings pane
}
```

**Steps:**

- [ ] **Step 1: Failing tests** with stub reader: `testReturnsPermissionItemWhenUntrusted`, `testFiltersMenuEntriesByQuery`, `testEntryTitleJoinsPath` ("File › Export…").
- [ ] **Step 2: Implement.** Activation: `AXUIElementPerformAction(element, kAXPressAction)`; panel is nonactivating so frontmost app keeps focus.
- [ ] **Step 3: Run tests + build** → PASS. **Step 4: Commit** `feat(launcher): menu bar item search with accessibility guard`

### Task 13: Final sweep

**Steps:**

- [ ] **Step 1:** Full `cargo test` untouched-check + full `xcodebuild test` (AtlasTests) → all PASS.
- [ ] **Step 2:** Grep for dangling references to deleted files (`CommandPaletteView`, `CommandPaletteController`) → none outside git history/docs.
- [ ] **Step 3:** Update `CLAUDE.md` ContentView/palette description + memory file `screenshot-snipaste-parity` untouched; add launcher note to `docs/superpowers/specs/2026-07-22-raycast-launcher-design.md` status header (状态:已实现).
- [ ] **Step 4: Commit** `docs: mark raycast launcher spec implemented`

## Self-Review

- Spec coverage: 外壳(T1-7)、样式自定义全项(T3/T11)、收藏/最近(T5)、alias/热键(T8)、quicklinks/fallback/参数(T9)、答案卡片(T2/T6)、Grid(T10)、详情侧栏(T2/T10)、菜单栏搜索(T12)、删旧面板(T7)、错误处理(源隔离 T5、热键冲突 T8、权限引导 T12)、测试清单齐。
- Types cross-checked: `LauncherItem.id` == usage key; builder signature evolves T5→T8→T9 (params added, callers updated in same tasks).
