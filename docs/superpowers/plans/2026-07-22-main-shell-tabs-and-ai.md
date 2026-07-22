# Main Shell Five-Tab + AI Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the main window into five top-level tabs (通用/插件/AI/设置/关于, ⌘1-⌘5) and ship a full AI center (multi-provider config + full-featured chat) with all shared logic in a new Rust crate `atlas-ai` exposed over UniFFI.

**Architecture:** Swift keeps only UI. `ContentView.mainShellView` gains a top tab bar routing to: the existing dashboard/library/tool trio (通用), `PluginsPanel` (插件), new `AIChat/` views (AI), new `SettingsTabView`/`AboutTabView` (设置/关于). Rust crate `atlas-ai` owns provider/session/preset CRUD + JSON storage, OpenAI-compatible SSE client with cancellation, and Markdown export; streaming reaches Swift via a UniFFI callback interface (SystemMonitorCallback pattern).

**Tech Stack:** SwiftUI, UniFFI (udl → `scripts/generate_uniffi_swift.sh`), reqwest 0.12 (json+stream), tokio (existing RUNTIME), serde/serde_json, base64.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-22-main-shell-tabs-and-ai-design.md`
- 主题硬性要求: all 16 `ShellThemeKind` themes preserved; theme picker (4-column) fully available in 设置 tab; every new tab view takes colors from the shell theme environment (`\.shellThemeKind`), no hardcoded palettes; forced appearance still applied at `mainShellView` level (new tabs inherit automatically).
- API keys never persisted by Rust; Swift stores them via `SecureLocalData` sealed file, passes per request.
- Rust storage root injected by host (`ai_set_storage_dir`); no platform path guessing in Rust.
- Menu-bar small panel mode untouched. `--main-window`, single-host migration untouched.
- New Swift files registered via `platforms/macos/tools/add_launcher_files.rb` (extend its glob list to `Atlas/MainShell/*.swift` and `Atlas/AIChat/*.swift`).
- Deviation from spec noted: 通用 tab's dashboard/library/tool bodies stay in `ContentView.swift` (they are entangled with ~50 ContentView members); only new-tab views live in `MainShell/`. Full ContentView split is follow-up work.
- Tests: `cargo test -p atlas-ai`; Swift via `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`.
- Commit after every task.

## File Structure

```
crates/atlas-ai/src/{lib.rs, models.rs, storage.rs, sse.rs, client.rs, export.rs}
crates/atlas-ffi/src/atlas.udl                 (+AI section)
crates/atlas-ffi/src/lib.rs                    (+AI impl)
platforms/macos/Atlas/MainShell/{ShellTab.swift, ShellTabBar.swift, SettingsTabView.swift, AboutTabView.swift}
platforms/macos/Atlas/AIChat/{AIChatBridge.swift, AIKeyVault.swift, AIProviderSettingsView.swift, AITabView.swift, AIChatTranscriptView.swift, AIComposerView.swift}
platforms/macos/AtlasTests/{ShellTabTests.swift, AIKeyVaultTests.swift, AIChatBridgeTests.swift}
```

---

### Task 1: atlas-ai crate — models + storage

**Files:** Create `crates/atlas-ai/Cargo.toml`, `src/lib.rs`, `src/models.rs`, `src/storage.rs`; modify root `Cargo.toml` members.

**Produces:**

```rust
pub struct ProviderConfig { pub id: String, pub name: String, pub base_url: String, pub model: String, pub extra_headers: Vec<HeaderPair> }
pub struct HeaderPair { pub name: String, pub value: String }
pub enum ChatRole { System, User, Assistant }
pub struct ChatMessage { pub id: String, pub role: ChatRole, pub text: String, pub image_paths: Vec<String>, pub timestamp_ms: i64, pub error: Option<String> }
pub struct ChatSession { pub id: String, pub title: String, pub created_at_ms: i64, pub preset_id: Option<String>, pub provider_id: Option<String>, pub messages: Vec<ChatMessage> }
pub struct PromptPreset { pub id: String, pub name: String, pub system_prompt: String }
pub struct AiStore { root: PathBuf }  // new(root), providers()/save_provider()/delete_provider(),
                                      // sessions_index() -> Vec<SessionSummary>, load_session(id), save_session(&ChatSession), delete_session(id),
                                      // presets()/save_preset()/delete_preset()
pub struct SessionSummary { pub id: String, pub title: String, pub created_at_ms: i64, pub message_count: u32 }
```

Storage layout: `<root>/providers.json`, `<root>/presets.json`, `<root>/sessions/<id>.json`. Corrupt file → that entity skipped, `Err(AiError::Corrupt(path))` surfaced for single-load, list ops skip+continue.

**Steps:**
- [ ] Failing tests in `storage.rs` `#[cfg(test)]` (tempdir via `std::env::temp_dir()` + uuid suffix): `provider_crud_roundtrip`, `session_crud_and_index`, `preset_crud`, `corrupt_session_file_skipped_in_index`, `load_corrupt_session_errors`.
- [ ] Implement; `cargo test -p atlas-ai` → PASS; commit `feat(ai): atlas-ai crate with provider/session/preset storage`.

### Task 2: SSE parser + Markdown export (pure)

**Files:** Create `src/sse.rs`, `src/export.rs`.

**Produces:**

```rust
pub enum SseEvent { Delta(String), Done, Other }
pub struct SseParser { buf: String }   // feed(&mut self, chunk: &str) -> Vec<SseEvent>
pub fn export_markdown(session: &ChatSession) -> String
```

Parser rules: split on `\n`, lines starting `data: `; payload `[DONE]` → `Done`; else JSON → `choices[0].delta.content` string → `Delta`; unparsable JSON → `Other`; partial trailing line stays in buf across feeds.

**Steps:**
- [ ] Failing tests: `parses_delta_stream` (two chunks splitting a line mid-way), `handles_done_marker`, `ignores_comments_and_unknown` (`: keepalive`, bad JSON), `export_markdown_snapshot` (session with system/user/assistant → expected literal string with `## User` / `## Assistant` headers + title H1).
- [ ] Implement; test PASS; commit `feat(ai): sse parser and markdown export`.

### Task 3: client — request build + streaming send + cancellation

**Files:** Create `src/client.rs`; extend `Cargo.toml` deps: `reqwest = { version = "0.12", default-features = false, features = ["json", "stream", "rustls-tls"] }`, `futures-util`, `base64`, `tokio`.

**Produces:**

```rust
pub struct SendRequest { pub base_url: String, pub api_key: String, pub model: String, pub extra_headers: Vec<HeaderPair>, pub system_prompt: Option<String>, pub messages: Vec<ChatMessage> }
pub fn build_body(req: &SendRequest) -> serde_json::Value   // pure: messages w/ system first; images → content parts w/ base64 data URLs (image file read; missing file → text-only + error note)
pub trait StreamSink: Send + Sync { fn on_delta(&self, text: String); fn on_done(&self); fn on_error(&self, message: String); }
pub async fn send_streaming(req: SendRequest, sink: Arc<dyn StreamSink>, cancel: tokio_util::sync::CancellationToken)
```

(uses `tokio_util` — add dep; on HTTP status != 2xx read body → `on_error("HTTP <code>: <body prefix 300>")`; network error → `on_error`; cancel → stop silently after `on_done` NOT fired, emit `on_error("cancelled")`? No — cancel emits `on_done` with partial kept: sink gets `on_done` so UI finalizes partial text.)

**Steps:**
- [ ] Failing tests (pure parts): `build_body_orders_system_first`, `build_body_encodes_image_data_url` (temp png bytes `[0x89,0x50,0x4E,0x47]` → `data:image/png;base64,...`), `build_body_missing_image_becomes_note`.
- [ ] Implement build_body + send_streaming (streaming path unit-tested indirectly through SseParser; no mock server dep).
- [ ] `cargo test -p atlas-ai` PASS; commit `feat(ai): openai-compatible streaming client with cancellation`.

### Task 4: FFI — udl + lib.rs + regenerate bindings

**Files:** Modify `crates/atlas-ffi/src/atlas.udl`, `crates/atlas-ffi/src/lib.rs`, `crates/atlas-ffi/Cargo.toml` (dep atlas-ai); run `scripts/generate_uniffi_swift.sh`.

**udl additions:**

```
dictionary AiProviderConfig { string id; string name; string base_url; string model; };
dictionary AiChatMessage { string id; string role; string text; sequence<string> image_paths; i64 timestamp_ms; string? error; };
dictionary AiSessionSummary { string id; string title; i64 created_at_ms; u32 message_count; };
dictionary AiChatSession { string id; string title; i64 created_at_ms; string? preset_id; string? provider_id; sequence<AiChatMessage> messages; };
dictionary AiPromptPreset { string id; string name; string system_prompt; };
callback interface AiChatStreamDelegate {
    void on_delta(u64 request_id, string text);
    void on_done(u64 request_id);
    void on_error(u64 request_id, string message);
};
namespace atlas {  // additions
    void ai_set_storage_dir(string path);
    [Throws=AtlasError] sequence<AiProviderConfig> ai_list_providers();
    [Throws=AtlasError] void ai_save_provider(AiProviderConfig provider);
    [Throws=AtlasError] void ai_delete_provider(string id);
    [Throws=AtlasError] sequence<AiSessionSummary> ai_list_sessions();
    [Throws=AtlasError] AiChatSession ai_load_session(string id);
    [Throws=AtlasError] void ai_save_session(AiChatSession session);
    [Throws=AtlasError] void ai_delete_session(string id);
    [Throws=AtlasError] sequence<AiPromptPreset> ai_list_presets();
    [Throws=AtlasError] void ai_save_preset(AiPromptPreset preset);
    [Throws=AtlasError] void ai_delete_preset(string id);
    [Throws=AtlasError] string ai_export_session_markdown(string id);
    u64 ai_send_message(string session_id, AiProviderConfig provider, string api_key, string? system_prompt, AiChatStreamDelegate delegate);
    void ai_cancel(u64 request_id);
};
```

lib.rs: `AI_STORE: Lazy<Mutex<Option<AiStore>>>`, `AI_REQUESTS: Lazy<Mutex<HashMap<u64, CancellationToken>>>`, counter `AtomicU64`. `ai_send_message` loads session, builds `SendRequest`, spawns on existing `RUNTIME`, wraps delegate in `StreamSink` adapter, on_done persists assistant message into session. Add `AiError` mapping into existing `AtlasError` (`"AiError"` variant).

**Steps:**
- [ ] udl + lib.rs; `cargo build -p atlas-ffi` PASS; `cargo test` all crates PASS.
- [ ] Run `scripts/generate_uniffi_swift.sh` (regenerates `platforms/macos/Generated/AtlasFFI/*` incl. fat `libatlas_ffi.a`); `xcodebuild build` PASS.
- [ ] Commit `feat(ffi): ai provider/session/preset + streaming chat surface`.

### Task 5: ShellTab + tab bar + ContentView routing

**Files:** Create `MainShell/ShellTab.swift`, `MainShell/ShellTabBar.swift`; modify `ContentView.swift` (`mainShellView`); extend `add_launcher_files.rb` globs; test `AtlasTests/ShellTabTests.swift`.

**Produces:**

```swift
enum ShellTab: String, CaseIterable, Identifiable { case general, plugins, ai, settings, about
    var title: String   // 通用/插件/AI/设置/关于
    var icon: String    // square.grid.2x2 / puzzlepiece.extension / sparkles / gearshape / info.circle
    var shortcutDigit: Int // 1...5
}
struct ShellTabBar: View { @Binding var selection: ShellTab }  // capsule segmented bar, theme-aware (reads \.shellThemeKind), .focusable(false)
```

ContentView: `@State private var shellTab: ShellTab = .general`; `mainShellView` body switches — `.general` → existing `shellPage` trio; `.plugins` → `PluginsPanel()`; `.ai/.settings/.about` → new views (placeholders until Tasks 6-8). ⌘1-5 via hidden `Button(...).keyboardShortcut(KeyEquivalent(Character("\(digit)")), modifiers: .command)` block inside mainShellView. Tab bar sits beside `shellTitlebarAccessory`.

**Steps:**
- [ ] Tests: `testFiveTabsOrdered`, `testShortcutDigitsUnique`, `testAllSixteenThemesStillRegistered` (`ShellThemeKind.allCases.count == 16`).
- [ ] Implement + wire; build + tests PASS; commit `feat(shell): five top-level tabs with cmd-1-5 switching`.

### Task 6: SettingsTabView (panel reuse + theme picker)

**Files:** Create `MainShell/SettingsTabView.swift`; modify `ContentView.swift` (mount), locate current theme picker (`grep -n "shellThemeRaw" ContentView.swift` — picker lives in shell settings sheet) and reuse the same `@AppStorage("atlas.shell.theme")` binding in a 4-column `LazyVGrid` picker component extracted as `ShellThemePickerGrid` (new, in SettingsTabView.swift).

Content: ScrollView two-column flow hosting existing panels — `ScreenshotFeatureSettingsPanel`, `TranslationSettingsPanel`, `TokenBarSettingsPanel`, `LauncherSettingsPanel` (+ hotkey `KeyRecorderView`), `AutomationSettingsView`, `SkillSettingsView` — same wiring as `AtlasSettingsView` (copy load/save funcs into a shared `SettingsPanelsHost` view reused by BOTH `AtlasSettingsView` and `SettingsTabView`; AtlasSettingsView body becomes `SettingsPanelsHost(...)` to avoid duplication).

**Steps:**
- [ ] Extract `SettingsPanelsHost` from AtlasSettingsView (move body+state, keep public init w/ paletteState); AtlasSettingsView delegates to it.
- [ ] SettingsTabView = ShellThemePickerGrid + SettingsPanelsHost.
- [ ] Build + full Swift tests PASS; commit `feat(shell): settings tab with theme picker and shared panels host`.

### Task 7: AboutTabView

**Files:** Create `MainShell/AboutTabView.swift`.

Content: app icon, name, `Bundle.main` short version+build, distribution channel label (`DistributionChannel` existing), Direct channel → "检查更新" button calling `DirectUpdateService().check()` async with result states (up-to-date / new version + download link / error "稍后再试"); Store channel → App Store link. Links: GitHub repo, privacy doc. All colors from theme environment.

**Steps:**
- [ ] Implement; build PASS; commit `feat(shell): about tab with update check`.

### Task 8: AIKeyVault + AIChatBridge

**Files:** Create `AIChat/AIKeyVault.swift`, `AIChat/AIChatBridge.swift`; tests `AIKeyVaultTests.swift`, `AIChatBridgeTests.swift`.

**Produces:**

```swift
final class AIKeyVault {                     // SecureLocalData-sealed file per provider
    init(directory: URL)                     // default: Application Support/Atlas/ai/keys
    func setKey(_ key: String?, providerID: String) throws
    func key(providerID: String) -> String?
}
@MainActor final class AIChatBridge: ObservableObject {
    @Published var providers: [AiProviderConfig]
    @Published var sessions: [AiSessionSummary]
    @Published var presets: [AiPromptPreset]
    @Published var activeSession: AiChatSession?
    @Published var streamingText: String     // in-flight assistant delta accumulation
    @Published var isStreaming: Bool
    @Published var lastError: String?
    init(vault: AIKeyVault = ..., storageDir: URL = ...)   // calls Atlas.aiSetStorageDir once
    func refresh(); func newSession(); func open(_ id: String); func delete(_ id: String); func rename(_ id: String, title: String)
    func send(text: String, imagePaths: [String])          // appends user msg, saves, aiSendMessage w/ delegate→main
    func cancel()
    func exportMarkdown() -> String?
    // provider/preset CRUD passthroughs
}
```

Delegate adapter class conforms to generated `AiChatStreamDelegate`, hops to main via `Task { @MainActor ... }` (SystemMonitorCallback pattern).

**Steps:**
- [ ] Tests: vault roundtrip/remove (temp dir); bridge delegate main-thread delivery with stubbed FFI? FFI global — test only vault + pure helpers (`AIChatBridge.title(for:)` first-line truncation). Keep bridge test to `testDeltaAccumulation` via internal `apply(delta:)` func.
- [ ] Implement; build + tests PASS; commit `feat(ai): key vault and chat bridge`.

### Task 9: AI UI — provider settings + chat panel

**Files:** Create `AIChat/AIProviderSettingsView.swift`, `AIChat/AITabView.swift`, `AIChat/AIChatTranscriptView.swift`, `AIChat/AIComposerView.swift`; mount `.ai` case in ContentView.

- AITabView: HSplit — left session list (new/delete/rename via context menu, selection opens) + preset picker + provider picker top bar + gear → provider settings sheet; right transcript + composer.
- Transcript: ForEach messages — user right-aligned card, assistant left with Markdown (`try? AttributedString(markdown:)` fallback plain), streaming bubble appends `streamingText`, error row with 重试 button (`resend last user msg`). Auto-scroll bottom.
- Composer: TextEditor(3-6 lines), image attach (fileImporter + paste/drop of file URLs → copy into storage dir /images), thumbnails row, Send (⌘↵) / Stop while streaming. Export button → NSSavePanel writes `exportMarkdown()`.
- ProviderSettings: list + form (name/baseURL/model/apiKey SecureField saved to vault), 连通性测试 button → `send` minimal 1-token request to `models` endpoint? Simpler: POST chat completions `max_tokens:1` non-stream via URLSession with 8s timeout, result label (DNS/超时/401 distinguished by URLError code / HTTP status).
- All views read `\.shellThemeKind` for accent/card styling; rows `.focusable(false)`.

**Steps:**
- [ ] Implement 4 views + mount; register files; build PASS; manual smoke via `--main-window` launch.
- [ ] Commit `feat(ai): provider settings and full chat panel`.

### Task 10: Final sweep

- [ ] `cargo test` all + full `xcodebuild test` → PASS.
- [ ] Spec status → 已实现;CLAUDE.md architecture note (atlas-ai crate + MainShell/AIChat dirs);memory file update;push.
- [ ] Commit `docs: mark main shell + AI center spec implemented`.

## Self-Review

- Coverage: 五 tab(T5)、主题保留(T5 测试+T6 picker+全视图环境取色)、插件内嵌(T5)、AI 配置中心(T9)、全功能对话=多会话/流式/图片/预设/导出/Markdown(T1-4 Rust,T8-9 UI)、Key 不进 Rust(T8 vault)、存储注入(T4/T8)、关于+更新(T7)、设置聚合复用(T6)、菜单栏面板不动(路由只改 isMainWindow 分支)。
- Types: `AiProviderConfig` udl 无 extra_headers(YAGNI:udl 层暂不暴露,Rust 结构保留字段默认空;Swift 表单不提供)——一致性:T3 build_body 接受空 headers。
- Placeholders: none。
```
