# Command Palette Shell — Design Spec

**Date:** 2026-05-21
**Status:** Approved

---

## Overview

Add a Raycast-style global command palette to Atlas. A configurable hotkey (default `⌥Space`) opens a floating search panel from anywhere on the screen. The panel provides two interaction modes: direct-execute commands (run and close) and push-navigation into sub-views. All existing Atlas features are exposed as commands, and macOS apps are searchable and launchable. This is the foundation for future modules (clipboard history, developer tools, snippets, window management) — each will add a `CommandProviding` implementation.

---

## Architecture

### Provider Protocol

```swift
protocol CommandProviding {
    func results(for query: String) -> [PaletteCommand]
}
```

Each feature module implements `CommandProviding` independently. `CommandPaletteController` holds an ordered `[CommandProviding]` array and aggregates results on each keystroke. Adding a new feature requires only implementing the protocol and registering one instance — no changes to existing code.

### Data Model

**`PaletteCommand`**
```
id: UUID
title: String
subtitle: String?
icon: PaletteIcon          // .sfSymbol(String) | .appIcon(URL)
keywords: [String]
action: PaletteAction
category: String           // "App" | "Atlas" | future categories
```

**`PaletteAction`**
```
.execute(() -> Void)        // run callback, then close palette
.push(PaletteDestination)   // navigate into sub-view, keep palette open
```

**`PaletteDestination`**
```
.windowPicker              // capturable window list for screenshot
.screenshotLibrary         // screenshot library with search
.portLookup                // port number input + process result
.custom(AnyView)           // reserved for future modules
```

---

## Window

- **Implementation:** `NSPanel` with `[.borderless, .nonactivatingPanel]`, level `.modalPanel`. Mirrors the pattern in `FloatingScreenshotThumbnailWindow`. Does not activate the Atlas app or dismiss the menu bar panel.
- **Position:** Horizontally centered on the main screen, top edge at 20% of screen height.
- **Size:** Width 640pt fixed. Height adapts: 52pt search bar + 52pt per visible result, capped at 8 results (~468pt max). Results beyond 8 scroll.
- **Background:** `.ultraThinMaterial` + 12pt corner radius + shadow.
- **Dismiss:** Escape key, click outside (global `NSEvent` `mouseDown` monitor), or `.execute` action completing.

---

## Search Bar

- Full-width at top of panel, 52pt height.
- Left: magnifying glass SF Symbol.
- Right: `←` back button when inside a sub-view (tapping pops navigation stack).
- Font: 17pt, no border, placeholder "Search Atlas…".
- In sub-views: becomes a local filter bound to the sub-view's search state.

---

## Results List

Each row (52pt height):
- Left: 32×32 icon (App `.icns` via `NSWorkspace` or SF Symbol in rounded rect background)
- Center: `title` (body weight) + `subtitle` (caption, secondary color)
- Right: `category` tag (caption, tertiary color)

Keyboard navigation: `↑` / `↓` arrows move selection, `Return` executes, `Tab` also executes.

**Merge and sort order:**
1. `AtlasCommandProvider` results first (Atlas features get priority)
2. `AppLauncherProvider` results second
3. Within each provider: exact prefix match → contains → fuzzy scored

When query is empty, show `AtlasCommandProvider` default list (no app results).

---

## Built-in Providers

### `AtlasCommandProvider`

Fixed command list. Matched by `title` prefix or `keywords` substring (case-insensitive). Registered callbacks come from `ContentView` via closures passed at init.

| Title | Keywords | Action |
|-------|----------|--------|
| Capture Desktop | screenshot, capture, desktop | `.execute` |
| Capture Area | screenshot, capture, area, region | `.execute` |
| Capture Window | screenshot, capture, window | `.push(.windowPicker)` |
| Screenshot Library | library, screenshots, history | `.push(.screenshotLibrary)` |
| Port Lookup | port, process, network | `.push(.portLookup)` |
| Toggle [feature] (×N) | toggle, enable, disable, [feature name] | `.execute` |
| Open Settings | settings, preferences | `.execute` |

### `AppLauncherProvider`

- Scans `/Applications` and `~/Applications` at init, caches `[(name: String, url: URL, icon: NSImage)]`.
- Search: score each app against query using simple fuzzy scorer (consecutive-match bonus + first-letter-match bonus). Return top 5.
- Action: `.execute { NSWorkspace.shared.open(url) }`.
- Icon: `NSWorkspace.shared.icon(forFile: url.path)`, scaled to 32×32.
- Refresh: rescans when `NSWorkspace.didMountNotification` or app install changes detected (optional v1 enhancement — acceptable to skip and only scan at launch).

---

## Navigation Stack

`CommandPaletteView` owns `@State var stack: [PaletteDestination] = []`.

- Selecting `.push(dest)` → `stack.append(dest)` with `.easeInOut(duration: 0.18)` slide-in from trailing edge.
- Escape or `←` button → `stack.removeLast()` with slide-out to trailing edge. If stack is empty, Escape closes the panel.
- Sub-views are full-width within the panel below the search bar.
- Sub-view content reuses existing SwiftUI components (`ScreenshotLibraryPanel`, port lookup logic) embedded as child views with `frame(maxHeight: 360)` + `ScrollView` wrap.

---

## Hotkey Configuration

**Storage:** `UserDefaults` keys `palette.hotkey.keyCode: Int` (default 49 = Space) and `palette.hotkey.modifiers: UInt` (default `NSEvent.ModifierFlags.option.rawValue`).

**`GlobalHotkeyService` extension:** Replaces single `onAreaCapture` callback with `[(keyCode: Int, modifiers: NSEvent.ModifierFlags, handler: () -> Void)]` array. `handle(_ event:)` iterates to find a match.

**`KeyRecorderView`:** SwiftUI view that shows the current shortcut as a styled badge. On click, enters recording mode (highlighted border, "Press shortcut…" text). Captures the next `keyDown` event with at least one modifier key. Validates: must include at least one of `⌘ ⌥ ⌃ ⇧`. Saves to `UserDefaults` and triggers hotkey service restart.

**Conflict check:** On save, warn (non-blocking) if the new shortcut matches `⌃⇧4` (area capture) or any other registered Atlas hotkey.

**Settings location:** New "Command Palette" section in `AtlasSettingsView`, showing the `KeyRecorderView`.

---

## File Structure

**New files (all added to the Atlas target):**

```
Atlas/
├── CommandPalette/
│   ├── CommandPaletteController.swift   // NSPanel lifecycle: show(), hide(), toggle()
│   ├── CommandPaletteView.swift         // SwiftUI root: search bar + results + nav stack
│   ├── CommandPaletteModels.swift       // PaletteCommand, PaletteAction, PaletteDestination, PaletteIcon
│   ├── CommandProviding.swift           // CommandProviding protocol
│   ├── AppLauncherProvider.swift        // /Applications scanner + fuzzy search
│   ├── AtlasCommandProvider.swift       // Atlas feature commands
│   └── KeyRecorderView.swift           // Hotkey capture UI component
```

**Modified files:**
- `GlobalHotkeyService.swift` — multi-hotkey support
- `AtlasApp.swift` — init `CommandPaletteController`, register providers
- `AtlasSettingsView.swift` — "Command Palette" settings section
- `ContentView.swift` — pass action closures to `AtlasCommandProvider`

---

## Testing

| Test file | What it covers |
|-----------|---------------|
| `CommandPaletteModelsTests.swift` | `PaletteCommand` equality, `PaletteAction` matching |
| `AppLauncherProviderTests.swift` | Fuzzy search scoring, result ordering, empty query returns empty |
| `AtlasCommandProviderTests.swift` | Query matching, keyword hits, empty query returns full default list |
| `GlobalHotkeyServiceTests.swift` | Multi-hotkey registration, correct handler fired, conflict detection |
| `KeyRecorderViewTests.swift` | Modifier validation, UserDefaults round-trip |

UI behaviour (panel show/hide, navigation stack, animation) is verified manually — no XCTest coverage for NSPanel lifecycle.

---

## Out of Scope (v1)

- Clipboard history commands (separate sub-project)
- Developer tool commands (separate sub-project)
- Window management commands (separate sub-project)
- Snippets (separate sub-project)
- Frecency-based result ranking (launch count tracking)
- App rescan on install/uninstall (acceptable to only scan at launch)
- Custom command aliases
