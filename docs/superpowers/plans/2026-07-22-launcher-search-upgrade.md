# Launcher Search Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fuzzy + pinyin matching with highlight, frecency ranking, async slow-source search, and panel UX upgrades (⌘digits, paging, section jump, alias badges, empty/loading states, animations) per `docs/superpowers/specs/2026-07-22-launcher-search-upgrade-design.md`.

**Architecture:** New pure `Launcher/Search/` engine annotates `LauncherItem` (transient `score` + `titleHighlights`). `LauncherItemSource` gains `searchMode`(.commandList/.queryDriven) + `isSlow`. A MainActor `LauncherSearchCoordinator` computes fast sources synchronously and slow ones on debounced background tasks with generation-based staleness; `LauncherSectionBuilder` keeps section semantics but consumes engine-annotated items and sorts by combined score. UI renders highlights/badges and new keyboard paths.

## Tasks

1. **Engine (pure, tested)**: `FuzzyMatcher.match(query:candidate:) -> (score: Double, ranges: [Range<String.Index>])?` — full-subsequence else nil; bonuses prefix/word-boundary/camel/consecutive, gap penalty. `PinyinIndexer.index(_:)` per-char CFStringTransform cached → full/initials + char spans; `bestMatch(query:text:)` tries original/full-pinyin/initials (×1.0/0.9/0.85) mapping highlights back to original chars. `FrecencyRanker.frecency(record:now:)` = count·e^(−ln2·Δt/7d); combined = match×0.7 + 100·(f/(f+1))×0.3. `LauncherSearchEngine.annotate(items:query:records:)` → filtered+scored copies (keywords hit ⇒ ×0.8, no title highlight). Tests: boundary>consecutive>scatter, nil miss, "jietu"/"jt"→截图 with ranges, decay halves at 7d, empty query frecency-only.
2. **Source modes + builder rework**: protocol ext defaults (`.commandList`, `isSlow=false`); adapter takes explicit mode; AtlasApp maps Calculator/Emoji/FileSearch/Clipboard→queryDriven (FileSearch/MenuBar isSlow). Builder: commandList sources engine-annotated; queryDriven passthrough (relevance guard retained); rank by score then frecency. Alias badge annotation. Existing tests updated.
3. **Async coordinator**: `LauncherSearchCoordinator` @Published sections/loadingSources; fast sync, slow debounced (150 ms) background w/ generation discard; error→empty+log. RootView binds coordinator (replaces body buildSections). Async tests with fake clock/sources.
4. **Panel UX**: title highlight AttributedString (accent+semibold); alias capsule; hold-⌘ index badges + ⌘1-9 run; PageUp/Down; ⌘↑/⌘↓ section jump; argument chip; empty-state icon animation + "试试 fallback" scroll; per-source spinner row; height/selection spring animations.
5. **Sweep**: full suites, spec 状态→已实现, memory, 打包重启, push.
