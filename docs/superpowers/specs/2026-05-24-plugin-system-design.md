# Atlas Plugin System — Architecture Design

**Date:** 2026-05-24
**Status:** Approved (design phase) — **partially built** as of 2026-06-17 audit: wasmtime exec, MCP client+stdio, Block Kit schema, SHA-256 verify are REAL; WIT Component Model bindings, Hub HTTP download, and capability-consent UX are NOT built. Third-party plugins are **direct-distribution only** (App Store forbids external code).
**Scope:** Full extensibility platform allowing third-party plugins to extend Atlas without recompilation.
**Unified context:** This doc owns the **Tier 3 extensibility** slice. See [`2026-06-17-modular-distribution-unified.md`](./2026-06-17-modular-distribution-unified.md) for how it composes with the dynamic loader, editions, and the channel split.

---

## 1. Motivation

Atlas currently has several **code-level** extension points but none are user-installable:

| Extension Point | Current State | User-Installable? |
|----------------|---------------|-------------------|
| `CommandProviding` protocol | 14 built-in providers | ❌ Requires recompile |
| `Skills` module | Built-in `SkillStore` + `SkillRuntime` | ⚠️ Built-in only |
| `Automation` module | Custom automations | ✅ User scripts supported |
| `Scene System` | Module overrides + behavior rules | ⚠️ Config layer only |

**Goal:** A formal plugin system letting users install third-party extensions that add new palette commands, panels, system integrations, and AI workflows — without recompiling Atlas.

---

## 2. Dual-Track Architecture

Atlas adopts a **two-track plugin model** to cover the full spectrum of use cases:

```
┌────────────────────────────────────────────────────────┐
│ Atlas Plugin System                                    │
├────────────────────────────────────────────────────────┤
│                                                        │
│  Track A: WASM Plugins                                 │
│    Use case: Lightweight, local computation            │
│    Examples: palette providers, text processors,       │
│              format converters, custom calculators     │
│    Tech:     wasmtime + WIT Component Model            │
│                                                        │
│  Track B: MCP Plugins                                  │
│    Use case: Heavy, external APIs, AI workflows        │
│    Examples: GitHub PR assistant, Linear ticket flow,  │
│              Figma review, Notion search               │
│    Tech:     Model Context Protocol (subprocess)       │
│                                                        │
└────────────────────────────────────────────────────────┘
```

### Why two tracks

| Aspect | WASM (Track A) | MCP (Track B) |
|--------|---------------|---------------|
| Performance | Sub-millisecond startup | Process startup overhead |
| Sandboxing | Memory + capability isolation | Process + capability isolation |
| Language | Rust, AssemblyScript, TinyGo | Any (Python, Node, Go, Rust) |
| System access | Via host API only | Native OS access (gated) |
| AI integration | Limited | Native (Tools, Resources, Prompts) |
| Ecosystem | New | Existing MCP servers reusable |
| UI capability | Block Kit schema | Block Kit schema |
| Best for | 90% utility plugins | Service integrations, AI |

---

## 3. UI Solution: Declarative Block Kit + WebView Escape Hatch

The core challenge: **WASM has no UI primitives, MCP plugins are headless.** Solution: plugins emit a UI **description**, Atlas renders it natively.

### 3.1 Three rendering tiers

```
Tier 1: Atlas Block Kit (recommended default, ~95% of plugins)
        Plugin emits JSON UI tree → SwiftUI renders natively
        Cross-platform by design (same JSON → GTK/WinUI/React)

Tier 2: Host-Provided Rich Components (~4%)
        Atlas pre-defines complex widgets: video player, rich text editor,
        charts, code editor. Plugin references by node type.

Tier 3: WebView Escape Hatch (opt-in, ~1%)
        Plugin ships HTML/CSS/JS bundle, Atlas embeds WKWebView.
        Officially supported as an opt-in escape hatch for the rare cases
        Block Kit can't express. Developer decides when to use it.
```

**Tier choice is the plugin author's call.** Atlas does not prevent WebView use; it simply documents the trade-offs so developers pick the right tier for their plugin.

### 3.1.1 When to choose WebView (Tier 3)

Use WebView when Block Kit genuinely cannot express the UI:

| Justified WebView use | Examples |
|----------------------|----------|
| Canvas / pixel-level drawing | Image annotation tool, color palette painter |
| 3D rendering | Model viewer, 3D scene editor |
| Custom interactive visualization | Network graph, dependency tree, mind map |
| Rich text editor with custom toolbar | Markdown WYSIWYG with custom blocks |
| Embedded third-party widgets | Stripe payment form, OAuth login flow |
| Existing web app integration | Wrapping a hosted dashboard |

**Discouraged WebView use** (Block Kit is the better fit):
- Simple forms, settings panels — use `text-field`, `toggle`, `slider`
- Lists with actions — use `list` with `on-select`
- Charts with standard types — use `chart` (bar/line/pie)
- File browsers — use Atlas's built-in file picker bridge

### 3.1.2 WebView trade-offs (informational)

| Aspect | Block Kit | WebView |
|--------|-----------|---------|
| Performance | Native (60fps) | 200ms+ first load, higher memory |
| Style consistency | Matches host HIG automatically | Plugin author maintains styling |
| Cross-platform | Same JSON works everywhere | Works everywhere WebView exists |
| Security surface | Limited to declared events | XSS / bridge attack surface |
| Iteration speed | Hot-reload friendly | Standard web dev cycle |
| Bundle size | Tiny (logic only) | Includes HTML+CSS+JS+assets |

Plugin authors should default to Block Kit and reach for WebView only when the UI genuinely cannot be expressed declaratively. Both are equally first-class in Atlas's plugin runtime.

### 3.2 Data flow

```
┌──────────────────┐                    ┌──────────────────┐
│ WASM Plugin      │                    │ Atlas Host       │
│ (no UI)          │                    │ (SwiftUI)        │
│                  │  ① render() →      │                  │
│ returns UI tree  │  ───────────────→  │ parses JSON,     │
│ (Component Model)│                    │ builds SwiftUI   │
│                  │                    │                  │
│                  │  ② user clicks btn │                  │
│                  │  ←───────────────  │                  │
│ on_event(id)     │                    │                  │
│ updates state    │                    │                  │
│                  │  ③ ui-update       │                  │
│                  │  ───────────────→  │ diff & re-render │
└──────────────────┘                    └──────────────────┘
```

This is **immediate-mode UI** with rendering pushed to the host — same pattern as Slack Block Kit, Microsoft Adaptive Cards, Raycast SDK.

### 3.3 Cross-platform implication

```
WASM Plugin → UI tree (pure data)
              │
              ├──→ macOS Atlas:   SwiftUI renderer
              ├──→ iOS Atlas:     SwiftUI renderer
              ├──→ Linux Atlas:   GTK / Slint renderer  (future)
              ├──→ Windows Atlas: WinUI renderer        (future)
              └──→ Web Atlas:     React renderer        (future)
```

The plugin author writes **once**, renders natively on every platform Atlas supports.

---

## 4. WASM Track — Technical Design

### 4.1 Runtime: wasmtime

Selected over wasmer because:
- Official Bytecode Alliance implementation, reference for WASI/Component Model
- Same Rust ecosystem as `atlas-core`
- Cranelift JIT performance
- Mature security audits

```toml
# crates/atlas-plugin-host/Cargo.toml
[dependencies]
wasmtime = "26"
wasmtime-wasi = "26"
wit-bindgen = "0.36"
```

### 4.2 Interface Definition: WIT (WebAssembly Interface Types)

WIT is the IDL for WASM Component Model — similar role to Protobuf but for WASM. Eliminates hand-written unsafe FFI glue.

```wit
// crates/atlas-plugin-host/wit/atlas.wit
package atlas:plugin@1.0.0;

// Host capabilities exposed to plugins
interface host {
    // Clipboard
    copy-to-clipboard: func(text: string);
    read-clipboard: func() -> option<string>;

    // Notifications
    show-notification: func(title: string, body: string);

    // Per-plugin storage
    storage-get: func(key: string) -> option<string>;
    storage-set: func(key: string, value: string);
    storage-delete: func(key: string);

    // Network (gated by capability)
    http-fetch: func(url: string, method: string,
                     headers: list<tuple<string, string>>,
                     body: option<string>) -> result<http-response, string>;

    // Logging
    log: func(level: log-level, message: string);
}

enum log-level { debug, info, warn, error }

record http-response {
    status: u16,
    headers: list<tuple<string, string>>,
    body: string,
}

// Plugin exports
interface plugin {
    metadata: func() -> plugin-metadata;
    init: func();
    shutdown: func();

    // Palette integration
    on-query: func(query: string) -> list<palette-item>;
    on-action: func(action-id: string, payload: string) -> action-result;

    // Panel UI (if plugin provides a panel)
    render: func() -> ui-node;
    on-event: func(event: ui-event) -> ui-update;
}

record plugin-metadata {
    name: string,
    version: string,
    description: string,
    capabilities: list<string>,
}

// UI node tree (recursive)
variant ui-node {
    vstack(vstack-props),
    hstack(hstack-props),
    section(section-props),
    text(text-props),
    button(button-props),
    text-field(text-field-props),
    slider(slider-props),
    toggle(toggle-props),
    select(select-props),
    list(list-props),
    image(image-props),
    color(color-props),
    chart(chart-props),
    code(code-props),
    spacer,
    // Tier 3 escape hatch — embed a WebView with plugin-provided assets
    webview(webview-props),
}

record webview-props {
    /// Plugin-relative path to HTML entry (resolved within plugin bundle)
    entry: string,
    /// Initial size hint (host may override based on container)
    width: option<f32>,
    height: option<f32>,
    /// Whether to allow JS-to-host bridge calls (requires `webview-bridge` capability)
    enable-bridge: bool,
}

variant ui-event {
    button-click(string),
    text-changed(text-event),
    slider-changed(slider-event),
    toggle-changed(toggle-event),
    select-changed(select-event),
    list-selected(list-event),
}

variant ui-update {
    rerender,
    patch(list<patch-op>),
    notification(notification),
    close,
    none,
}

world atlas-plugin {
    import host;
    export plugin;
}
```

### 4.3 Block Kit Component Vocabulary

Initial component set (extensible):

| Layout | Input | Display | Interaction |
|--------|-------|---------|-------------|
| `vstack` | `text-field` | `text` | `button` |
| `hstack` | `slider` | `image` | `list` (with on-select) |
| `section` | `toggle` | `chart` | `actions` (button group) |
| `spacer` | `select` | `code` | |
| `grid` | `color` | `progress` | |

### 4.4 Language Support

| Tier | Language | Toolchain | Rationale |
|------|----------|-----------|-----------|
| 1st-class | **Rust** | `cargo-component` | Best performance, smallest binary, official `atlas-plugin-bindings` crate |
| 1st-class | **AssemblyScript** | `asc` | Attracts JS/TS developers, npm `@atlas/bindings` package |
| Community | **TinyGo** | `tinygo build -target=wasi` | Familiar to Go developers |
| Community | **Python** | `componentize-py` | Lower performance but huge ecosystem |
| Community | **Zig**, **C/C++** | wasi-sdk | Power users only |

Atlas team officially maintains Rust + AssemblyScript bindings. Other languages are user-supported.

### 4.5 Example: Translator Plugin (Rust)

**Project structure:**
```
my-translator/
├── Cargo.toml
├── plugin.toml          # Atlas plugin manifest
└── src/lib.rs
```

**`plugin.toml`:**
```toml
name = "translator"
version = "0.1.0"
description = "Quick text translation"
author = "Jay"

[capabilities]
network = ["api.deepl.com"]
storage = true
clipboard = true
```

**`src/lib.rs`:** (abbreviated, full version in WASM Plugin section above)
```rust
use atlas_plugin_bindings::*;

impl plugin::Guest for Translator {
    fn metadata() -> plugin::PluginMetadata { ... }
    fn render() -> ui::UiNode { /* emit UI tree */ }
    fn on_event(event: ui::UiEvent) -> ui::UiUpdate { /* handle */ }
    fn on_query(query: String) -> Vec<plugin::PaletteItem> { /* palette */ }
    fn on_action(action_id: String, payload: String) -> plugin::ActionResult { ... }
}

plugin::export!(Translator with_types_in plugin);
```

**Build:**
```bash
cargo component build --release
# Output: target/wasm32-wasip2/release/my-translator.wasm
```

---

## 5. MCP Track — Technical Design

### 5.1 Why MCP

Atlas's AI-native positioning makes MCP a natural fit:
- Existing ecosystem of MCP servers (1000+ on GitHub)
- Native concepts of Tools, Resources, Prompts
- Subprocess isolation = crash containment
- Language-agnostic protocol

### 5.2 Integration model

```
┌─────────────────────────────────┐
│ Atlas (MCP Client)              │
├─────────────────────────────────┤
│ PluginManager                   │
│   ├── MCPSession (stdio)        │
│   │   ↕ JSON-RPC                │
│   ├── Tool registration         │
│   ├── Resource subscription     │
│   └── Prompt template usage     │
└──────┬──────────────────────────┘
       │ stdin/stdout
       ▼
┌─────────────────────────────────┐
│ MCP Server (Plugin)             │
│ (Python / Node / Rust / etc.)   │
│                                 │
│ Implements MCP spec:            │
│   - tools/list, tools/call      │
│   - resources/list, get         │
│   - prompts/list, get           │
└─────────────────────────────────┘
```

### 5.3 MCP Plugin manifest

```toml
# mcp-plugin.toml
name = "github-assistant"
version = "0.2.0"
description = "GitHub PR review and triage"

[runtime]
type = "mcp"
command = "node"
args = ["index.js"]

[capabilities]
network = ["api.github.com"]
exposed_tools = ["create_pr", "review_pr", "list_issues"]
```

### 5.4 UI surface for MCP plugins

MCP plugins reuse the same Block Kit UI schema as WASM plugins. The plugin's `tools/call` response can return:
- Plain text (rendered as palette item or notification)
- Block Kit UI tree (rendered as panel)
- Resource reference (Atlas renders inline)

This unifies UI behavior across both plugin tracks.

---

## 6. Plugin Lifecycle

```
┌───────────────────────────────────────────────────────┐
│  1. INSTALL                                           │
│     User installs plugin (from GitHub URL or Atlas Hub)│
│     Atlas downloads, verifies signature, extracts     │
│                                                       │
│  2. MANIFEST PARSE                                    │
│     Read plugin.toml, check capabilities, prompt user │
│     for permission consent (capability gating)        │
│                                                       │
│  3. INIT                                              │
│     For WASM:  load .wasm, instantiate wasmtime store │
│                call plugin.init()                     │
│     For MCP:   spawn subprocess, initialize MCP       │
│                handshake                              │
│                                                       │
│  4. RUNTIME                                           │
│     Plugin registers palette commands, panels,        │
│     subscribes to events. Atlas dispatches calls      │
│     based on user actions.                            │
│                                                       │
│  5. UPDATE                                            │
│     Atlas periodically checks for new versions,       │
│     prompts user to update if found                   │
│                                                       │
│  6. SHUTDOWN                                          │
│     Plugin disabled or uninstalled:                   │
│     call plugin.shutdown(), release resources         │
└───────────────────────────────────────────────────────┘
```

---

## 7. Permission Model (Capability System)

Plugins declare required capabilities in `plugin.toml`. Atlas enforces at the host API boundary.

### 7.1 Capability tiers

| Tier | Examples | Consent Model |
|------|----------|---------------|
| **Harmless** | clipboard read, storage, log | Auto-allowed on install |
| **Sensitive** | network (specific hosts), file read (sandboxed dir), notifications, `webview` (embed WebView) | Confirmed at install time |
| **Dangerous** | full file system, system commands, accessibility, `webview-bridge` (JS↔host RPC) | Per-use confirmation prompt |
| **Forbidden** | Process spawn (for WASM), keychain | Not exposed to plugins |

The `webview` capability lets the plugin render a WebView node. The separate `webview-bridge` capability is needed if the plugin wants the embedded JS to call back into the WASM/MCP plugin code (bidirectional communication). Plugins that just show static HTML/CSS visuals do not need `webview-bridge`.

### 7.2 Network capability granularity

```toml
[capabilities]
network = ["api.deepl.com", "translate.googleapis.com"]
# Plugin can ONLY reach these hosts; all other URLs rejected by host
```

### 7.3 Capability enforcement

Atlas's host API checks the calling plugin's capability list before executing:
```rust
fn http_fetch(plugin_id: PluginId, url: &str, ...) -> Result<Response> {
    let allowed_hosts = registry.capabilities(plugin_id).network;
    let host = url::Url::parse(url)?.host_str().unwrap();
    if !allowed_hosts.contains(host) {
        return Err("network capability denied".into());
    }
    // proceed with fetch
}
```

---

## 8. Distribution

### 8.1 Three install paths

```
1. Direct URL install
   atlas plugin install https://github.com/user/atlas-translator
   → clone, verify, install

2. Local file install
   atlas plugin install ./my-plugin.wasm
   → for plugin development

3. Atlas Hub (future)
   atlas plugin install translator
   → resolved from official registry
```

### 8.2 Plugin package format

```
my-plugin.atlasplugin/   (zip file with .atlasplugin extension)
├── plugin.toml          # Manifest
├── plugin.wasm          # WASM binary (for Track A)
│   OR
├── server.js + ...      # MCP server files (for Track B)
├── icon.png             # 64x64 plugin icon
├── README.md            # Description shown in UI
├── LICENSE              # Required
└── web/                 # Optional: WebView assets (Tier 3 only)
    ├── index.html
    ├── styles.css
    ├── app.js
    └── assets/
```

The optional `web/` directory holds HTML/CSS/JS bundles referenced by `webview` UI nodes. Atlas serves these from a sandboxed `atlas-plugin://` URL scheme — plugins cannot reach the host filesystem via WebView fetches.

### 8.3 Signing & verification (future)

- Atlas Hub plugins: signed by Atlas team
- Self-published: signed by author's GPG key
- Unsigned: warning on install

---

## 9. Integration with Atlas Modules

The plugin system integrates with all existing Atlas modules:

| Atlas Module | Plugin Integration |
|--------------|-------------------|
| Command Palette | Plugins can register palette providers |
| Skills | Plugins can ship as Skills with AI templates |
| Scene System | Plugins can declare scene-controllable settings |
| Flow Inbox | Plugins can subscribe to incoming items |
| Privacy Pulse | Plugin API access is logged for transparency |
| Automation | Plugins can register custom automation actions |
| Tokenbar | MCP plugin usage tracked for AI cost |

---

## 10. Implementation Phases

### Phase α — Foundation (4-6 weeks)
- New `atlas-plugin-host` Rust crate with wasmtime integration
- WIT interface definition + binding generation
- Plugin manifest parsing
- Capability enforcement at host API boundary
- Plugin install/uninstall CLI

### Phase β — UI Rendering (3-4 weeks)
- `PluginUIRenderer` SwiftUI component
- Block Kit node-to-SwiftUI mapping (vstack, hstack, button, text-field, slider, etc.)
- Event dispatch from SwiftUI back to WASM
- Patch-based incremental updates
- WebView escape hatch (Tier 3): `WKWebView` wrapper, `atlas-plugin://` URL scheme, optional JS↔host bridge gated by `webview-bridge` capability

### Phase γ — Palette + Module Integration (2-3 weeks)
- Plugin palette provider registration
- Plugin panel display in main window
- Scene System override exposure for plugins
- Per-plugin settings UI

### Phase δ — MCP Track (3-4 weeks)
- MCP subprocess host
- Tool/Resource/Prompt registration
- Block Kit UI schema interop with MCP responses

### Phase ε — Distribution (2-3 weeks)
- Plugin install CLI (URL, file, future Hub)
- Update checker
- Plugin signing infrastructure

### Phase ζ — Atlas Hub (future, separate spec)
- Official plugin registry website
- Submission flow, review process
- Search, ratings, install metrics

**Total estimate:** 14-20 weeks before first public plugins ship.

---

## 11. Out of Scope (for first version)

- Plugin-to-plugin communication (use Atlas as broker if needed)
- Native UI components from plugins (use Block Kit only)
- Background plugin execution (plugins run on-demand)
- Multi-window plugins (single-panel only initially)
- Plugin debugging UI (use `wasm-tools` and host logs)
- Plugin monetization / paid plugins

---

## 12. Open Questions

These remain to be decided:

1. **Marketplace governance** — Allow any GitHub repo? Curated registry? Both?
2. **WASM binary size limit** — Cap plugin size? (e.g., 10MB max)
3. **MCP plugin auto-update** — How aggressive? Daily check? Manual?
4. **Plugin telemetry** — Should plugin developers see anonymous usage stats?
5. **Compatibility policy** — Semver for the plugin API? Deprecation cycle?

---

## 13. Technical Dependencies

| Tool | Purpose | Source |
|------|---------|--------|
| `wasmtime` | WASM runtime | crates.io |
| `wasmtime-wasi` | WASI 0.2 support | crates.io |
| `wit-bindgen` | WIT → Rust binding gen | crates.io |
| `cargo-component` | Build Rust as WASM Component | bytecodealliance |
| `wasm-tools` | WASM debugging/inspection | bytecodealliance |
| `mcp-rust-sdk` | MCP client implementation | modelcontextprotocol.io |

---

## 14. References

- WASM Component Model: <https://component-model.bytecodealliance.org/>
- WIT spec: <https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md>
- Model Context Protocol: <https://modelcontextprotocol.io/>
- wasmtime: <https://wasmtime.dev/>
- Slack Block Kit (UI inspiration): <https://api.slack.com/block-kit>
- Microsoft Adaptive Cards: <https://adaptivecards.io/>
- Raycast Extensions (architecture inspiration): <https://developers.raycast.com/>
