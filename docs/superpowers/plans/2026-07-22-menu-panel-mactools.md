# Menu Panel MacTools-Style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the menu bar panel (homeView + fullPanelView) with a MacTools-style dual panel: top-center 功能/组件 switcher, feature row list with bottom fixed rows, and a configurable widget board — all themed via ShellTheme.

**Architecture:** New `MenuPanel/` module holds pure UI pieces; ContentView keeps ownership of state/actions and feeds the panel row models + a `sectionBuilder` closure (existing `primaryPanelSection(_:)`) for chevron sub-pages. Widget data reuses the existing `SystemSnapshot` (disks/battery already present — **no Rust changes needed**, spec's "磁盘新增采集" is already satisfied) plus `BluetoothBatteryService`.

**Tech Stack:** SwiftUI, ShellTheme environment, UserDefaults JSON persistence, XCTest.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-22-menu-panel-mactools-design.md`
- Theme: all views read `\.shellThemeKind` / use `.glassCard`; no hardcoded palettes; rows/cards `.focusable(false)`.
- ContentView private members stay private — MenuPanel gets data via row models and closures, never direct member access.
- Register new files via `platforms/macos/tools/add_launcher_files.rb` (extend dirs list with `MenuPanel` + `MenuPanel/Widgets`, tests glob `MenuPanel*Tests.swift` + `Widget*Tests.swift` + `Lunar*Tests.swift`).
- Tests: full `xcodebuild test` green at每 task end; commit after every task.

## File Structure

```
platforms/macos/Atlas/MenuPanel/
├── MenuPanelModels.swift      # PanelMode(.features/.widgets), WidgetKind, FeatureRowModel(+control enum)
├── WidgetStore.swift          # enabled widget kinds + order, JSON in UserDefaults, default [gauges, network]
├── LunarCalendar.swift        # chinese-calendar day label ("初八"/"廿三"…) pure helper
├── MenuPanelView.swift        # container: switcher + mode content + bottom fixed rows + sub-page push
├── FeatureListPanel.swift     # rows list (grouped)
├── FeatureRow.swift           # row: icon/title/subtitle + trailing toggle|chevron|capsule action
├── WidgetBoardPanel.swift     # widget card flow + "+ 添加组件"
├── WidgetGalleryView.swift    # gallery sheet: five widgets, add/added-greyed
└── Widgets/ (GaugeQuadWidget, NetworkWidget, ProcessTopWidget, CalendarWidget, DeviceBatteryWidget)
platforms/macos/AtlasTests/{MenuPanelStoreTests.swift, LunarCalendarTests.swift, MenuPanelRowMappingTests.swift}
```

### Task 1: Models + WidgetStore + LunarCalendar (+tests)

`WidgetKind: String CaseIterable Codable { gauges, network, processTop, calendar, deviceBattery }` with `title`/`icon`/`summary`. `WidgetStore: ObservableObject` — `@Published private(set) var enabled: [WidgetKind]`, `add/remove/move`, UserDefaults key `menuPanel.widgets`, garbage → default `[.gauges, .network]`. `FeatureRowModel { id, icon, title, subtitle?, control }`, `enum FeatureRowControl { toggle(Binding<Bool>), chevron(PrimaryPanelSection→made generic: assoc value is an opaque `AnyHashable` tag), action(label: String, run: () -> Void) }` — chevron tag is `AnyHashable` so the model file stays decoupled from ContentView's private enum; ContentView maps tag→section itself. `LunarCalendar.dayLabel(for: Date) -> String` (chinese calendar; day 1 → "初一", 11 → "十一", 20 → "二十", 21 → "廿一", 30 → "三十"; month day1 shows month name "五月"). Tests: store CRUD/order/persist/garbage-fallback; lunar labels for fixed dates (2026-06-13 → "廿八" per MacTools screenshot, 2026-06-15 → "五月").

### Task 2: Widget views + board + gallery

Five widget views take plain value inputs (no service types): `GaugeQuadWidget(cpu: Double?, memUsed/memTotal, diskUsed/diskTotal, battery: (percent: Double, charging: Bool)?)` ring gauges 2×2/4-across, `--` when nil + "开启监控" button hook `onEnableMonitoring: (() -> Void)?`; `NetworkWidget(downBps, upBps, lanIP: String?)` (LAN IP via `getifaddrs` helper in same file); `ProcessTopWidget(rows: [(name, cpu, mem)])`; `CalendarWidget()` self-contained month grid + lunar labels + today highlight + ←/→ month nav; `DeviceBatteryWidget(devices: [(name, icon, percent)], empty state text)`. `WidgetBoardPanel(store:, content: (WidgetKind) -> AnyView)` renders in order, context menu 移除/上移/下移, bottom "+ 添加组件" → sheet `WidgetGalleryView(store:)`. All `.glassCard`.

### Task 3: FeatureRow + FeatureListPanel + MenuPanelView

`FeatureRow(model:)` — 38pt row, icon in rounded square, trailing control by case (capsule action = accent-tinted button). `FeatureListPanel(groups: [(title: String?, rows: [FeatureRowModel])])`. `MenuPanelView`: top-center capsule switcher (功能/组件, `@AppStorage("menuPanel.mode")`), content per mode, bottom fixed rows (打开主窗口/设置/退出 — closures), sub-page: `@Binding pushedTag: AnyHashable?` + `sectionBuilder: (AnyHashable) -> AnyView` + back header (chevron style like launcher). Build passes.

### Task 4: ContentView wiring + delete old panels

In ContentView: `menuPanelRowGroups()` builds groups — 动作行(截屏三连+清空剪贴板历史), 开关行(KeepAwake/演示模式/窗口管理/剪贴板历史 + FeatureCenter toggles via `$enabledFeatures` bindings + `handleFeatureChange`), 箭头行(每个 `orderedPrimarySections()` section 一行, tag = section). `fullPanelView`/`homeView` bodies replaced by `MenuPanelView(...)`(`showsHome` state removed;capture status banner 保留在面板顶部). Widget data mapped from `snapshot` + `BatteryHealthService`/`BluetoothBatteryService` (instantiate/reuse existing service members). Old AtlasShellView usage removed; delete `AtlasShellView` file if now unreferenced (grep first). Row-mapping completeness test: every `PrimaryPanelSection.allCases` appears in chevron rows OR the documented exclusion list (`editionPanel` 类不在 enum 内则清单为空). Full Swift tests PASS.

### Task 5: Final sweep

Full cargo + xcodebuild tests; spec 状态→已实现(注明磁盘字段本就存在,Rust 零改动);CLAUDE.md MenuPanel note;memory;push.

## Self-Review

Coverage: 双面板+切换器(T3)、行列表+底部固定(T3/T4)、组件可添加/移除/排序+持久化(T1/T2)、五组件(T2)、主题硬性(全任务)、空态/监控引导(T2)、行映射测试(T4)、Rust 磁盘(已存在,T5 spec 备注)。Types: chevron tag AnyHashable 贯穿 T1/T3/T4。
