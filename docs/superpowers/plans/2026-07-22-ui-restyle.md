# UI Restyle (MacTools + Raycast) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four-tab main window (通用/插件/AI/关于) restyled per MacTools/Raycast screenshots: plain default theme, settings row-cards, sidebar plugins tab with commands table + market, dual-engine AI config (local CLI + BYOK).

**Architecture:** New `SettingsComponents` primitives + `plain` ShellTheme drive the look. `ShellTab` shrinks to four; 通用 absorbs the old 设置 tab; 插件 becomes sidebar layout hosting dashboard/menu-panel-config/commands-table/market/tool-settings; AI config sheet gains 本机 CLI | BYOK segmented modes backed by new `atlas-ai/src/cli.rs` (detection + subprocess streaming over the existing `AiChatStreamDelegate`).

**Tech Stack:** SwiftUI, ShellTheme registry, UniFFI regen, tokio Command streaming, SMAppService.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-22-ui-restyle-mactools-raycast-design.md`
- 17 themes total after adding `plain`; plain is default for fresh installs only (`@AppStorage` default value change; stored prefs win).
- All new views read theme env; `.focusable(false)` on rows.
- Register files via `add_launcher_files.rb`; tests glob already covers `ShellTab*`/`AI*`/`MenuPanel*` — add `Settings*Tests.swift`.
- Full test suites green each task; commit per task.

## Tasks

### Task 1: plain theme + SettingsComponents + four-tab collapse
- `ShellTheme.swift`: add `case plain` (first in CaseIterable order), spec: colorScheme nil, solid background (light `Color(nsColor: .windowBackgroundColor)` layered w/ subtle gray, dark system), card tokens flat (secondary bg, 1px border, no blur), icon "rectangle.grid.2x2", swatch grays. Default: `@AppStorage("atlas.shell.theme") = ShellThemeKind.plain.rawValue` in ContentView + anywhere else the default literal appears (grep `ShellThemeKind.aurora.rawValue`).
- `MainShell/SettingsComponents.swift`: `IconTile(systemImage, tint)`, `SettingsRow(icon, tint, title, description?, trailing: AnyView?)`, `SettingsCard { rows }`, `SettingsSection(title) { card }`.
- `ShellTab`: cases → general/plugins/ai/about (设置删除, ⌘1-4); 通用 icon "gearshape", title 通用.
- ContentView routing: `.general` → `GeneralSettingsTab` (Task 2 placeholder first), old general tool-shell trio moves under Plugins tab (Task 3) — for this task keep `.plugins` rendering old trio temporarily to stay shippable.
- Tests: `ShellTabTests` update (4 tabs, digits 1-4), theme count 17, plain spec sanity.
- Commit `feat(shell): plain theme, settings components, four-tab collapse`.

### Task 2: 通用 tab
- `MainShell/GeneralSettingsTab.swift`: sections 启动(SMAppService toggle w/ error text)、外观(appearance segmented — writes `NSApp.appearance` override AppStorage `atlas.appearance` auto/dark/light applied in AtlasApp;主题 17-grid = existing ShellThemePickerPanel embedded;语言占位)、启动台(hotkey recorder、样式自定义 disclosure → LauncherSettingsPanel、命令管理跳转按钮 → switch tab .plugins + sidebar 命令)、功能设置(SettingsPanelsHost 面板群包卡).
- Standalone settings window reuses (AtlasSettingsView unchanged content-wise).
- Tests: `SettingsComponentsTests` (row model/appearance storage roundtrip).
- Commit `feat(shell): mactools-style general settings tab`.

### Task 3: 插件 tab sidebar
- `MainShell/PluginsTab.swift`: `PluginsSidebarItem { dashboard, menuPanel, commands, market, tool(PrimaryPanelSection) }`; List sidebar 220pt + detail.
- 仪表盘: reuse ContentView `shellDashboard`/`shellLibrary`/`shellToolPage` trio (passed as AnyView closure from ContentView, same pattern as menu panel sectionBuilder).
- 功能面板: WidgetStore enable/reorder rows + widget gallery inline (reuse WidgetGalleryView guts).
- 命令: `CommandsTableView` — search field + category chips + Table(名称/分类/Alias TextField/热键 KeyRecorder/收藏 toggle) over `allRootItems()` + Alias/Hotkey stores + FavoritesStore.
- 市场: restyle PluginsPanel content: search + 分类 chips(计数) + sort menu + install cards (keep PluginsService API).
- 工具设置: sections list → detail = `primaryPanelSection(section)` + permissions header rows (AXIsProcessTrusted / CGPreflightScreenCaptureAccess relevant sections only).
- Tests: sidebar item registry, command row mapping (alias write-through).
- Commit `feat(shell): plugins tab with sidebar, commands table, market restyle`.

### Task 4: Rust cli.rs + FFI
- `atlas-ai/src/cli.rs`: `CliKind` builtin list (claude/codex/gemini/opencode/aider: binary, display, subtitle, default_models, version_args, prompt template), `detect_clis(paths: Vec<String>) -> Vec<DetectedCli>` (search dirs + `--version` capture, parse first semverish token), `run_prompt_via_cli(...)` tokio Command spawn, stdout line streaming; claude stream-json branch parses `{"type":"content_block_delta","delta":{"text":...}}` and assistant message events; cancel kills child.
- FFI: `AiDetectedCli` dict, `ai_detect_clis()`, `ai_send_via_cli(session_id, cli_id, cli_path, model?, delegate) -> u64`, `AiProviderConfig.max_tokens: u32?` (client body includes when set). Regen bindings.
- Tests: list integrity, version parse fixtures, stream-json parse fixtures, max_tokens in body, detect on empty dirs → [].
- Commit `feat(ai): local cli engine (detect + streaming) and max_tokens`.

### Task 5: AI config dual-engine UI + routing
- `AIChat/AIEngineStore.swift`: `AiEngine { case cli(id: String, path: String, model: String?) ; case byok(providerID: String) }` Codable + UserDefaults.
- `AIChat/AIConfigSheet.swift`: segmented 本机 CLI | BYOK. CLI page: scanned cards (icon/name/subtitle/version), selected = accent border + model picker + 测试; 重新扫描. BYOK page: preset chips grid (`ByokPreset` list: name/baseURL/defaultModel/keyURL) → form (网关预设/API Key + 显示 + 获取 key link/Base URL/max tokens/模型) → saves provider + vault key.
- `AIChatBridge`: `engine` published; `send` routes cli → `aiSendViaCli`, byok → existing; 测试 button = 1-token send w/ result label.
- Replace AIProviderSettingsView entry w/ AIConfigSheet (keep old provider list management inside BYOK page).
- Tests: engine codec, preset→form mapping.
- Commit `feat(ai): dual-engine config (local CLI / BYOK) with routing`.

### Task 6: Final sweep
- Full suites; spec 状态→已实现; CLAUDE.md/memory update; 打包重启; push.

## Self-Review
Coverage: 四 tab(T1)、素雅默认+17(T1)、通用行卡(T2)、插件侧栏五区(T3)、命令表格(T3)、市场重排(T3)、权限区(T3)、CLI 探测/流式(T4)、BYOK 预设+max_tokens(T4/5)、引擎路由(T5)、错误处理(各任务)、独立设置窗共用(T2)。
