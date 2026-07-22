# JS Plugin Track + Cross-Platform Native UI Strategy

**Date:** 2026-07-20
**Status:** Approved (design phase)
**Scope:** Adds a third plugin track (embedded JS engine) to the dual-track plugin system, formalizes the cross-platform UI strategy (schema + per-platform native renderers), records the LynxJS evaluation, and defines the Raycast compatibility strategy.
**Extends:** [`2026-05-24-plugin-system-design.md`](./2026-05-24-plugin-system-design.md) (Tracks A/B), [`2026-06-17-modular-distribution-unified.md`](./2026-06-17-modular-distribution-unified.md) (packaging/channel model).

---

## 1. Decisions at a glance

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Cross-platform UI = **UI schema (Block Kit) + one native renderer per platform** (SwiftUI / WinUI 3 / GTK-or-Qt). Plugins never touch platform APIs. | Only architecture that satisfies all three: any-language plugins, true native controls, cross-platform. Raycast-for-Windows validates it (same plugin API, per-platform native host). |
| D2 | Promote the Block Kit schema from a macOS implementation detail to a **Rust core crate (`atlas-ui-schema`)** — single source of truth; each shell consumes it. | Each new platform then costs one shell + one renderer; the plugin ecosystem is inherited for free. |
| D3 | Add **Track C: embedded JS plugins** on a QuickJS-family engine via `rquickjs` (QuickJS-NG bindings), behind a `JsEngine` trait. PrimJS is a possible future backend, not the initial one. | JS is the lowest-friction authoring track (Raycast-shaped ecosystem). PrimJS direct embedding rejected for now (see §4). |
| D4 | **ExtensionKit and dylib rejected** for third-party native UI. ExtensionKit is macOS-13+-only (fails cross-platform); dylib is unsandboxed, ABI-fragile, App-Store-forbidden. | ExtensionKit may return later as a macOS-only escape hatch; not part of the core plugin contract. |
| D5 | **LynxJS rejected as a plugin UI runtime; adopted as an architecture reference** (dual-thread model, main-thread-script escape, element-tree diff protocol). | On desktop Lynx renders with its own self-drawn engine (Clay), not native widgets — same disqualifier as Flutter. See §3. |
| D6 | **Raycast compatibility in two phases**: Phase 1 (now) — native JS API deliberately shaped like `@raycast/api` + a codemod migration tool. Phase 2 (conditional) — full Node-based compat runtime, direct-distribution only. | Vicinae (C++/Qt launcher, 8.5k★) proves a compat runtime is feasible and a growth lever, but it carries a permanent API-chasing tax and requires unsandboxed Node. Do not pay until ecosystem cold-start demands it. |
| D7 | **Trust tiers**: store-signed plugins may be granted wide capabilities (e.g. `shell.exec` with confirmation); sideloaded plugins are locked to the strict sandbox. Fully untrusted / unreviewed distribution is WASM-track-only. | Middle path between Raycast's zero-sandbox + store-review model and a pure capability sandbox: safer than Raycast, easier to grow than sandbox-only. |

The "three-way trade-off law" that drives D1/D4: **any-language plugins / true native UI / arbitrary custom UI — pick at most two.** Atlas picks the first two; Tier 3 WebView (existing spec §3.1) remains the documented escape hatch for the third.

---

## 2. Track landscape after this spec

```
Track A  WASM (wasmtime + WIT)      — compute kernels, polyglot authors, UNTRUSTED code
Track B  MCP (subprocess)           — heavy integrations, AI workflows, resident processes
Track C  JS (QuickJS via rquickjs)  — NEW: glue/API/UI-logic plugins, lowest authoring friction
(Track D — optional, Phase-2 only:  Node compat runtime for unmodified Raycast extensions)
```

All tracks emit the same `atlas-ui-schema` tree; the renderer cannot tell which runtime produced the UI.

### Track selection table (plugin-author-facing)

| Plugin shape | Track |
|---|---|
| Call API + render list/detail (the 90% case) | C (JS) |
| Local pure-compute tool (encode/format/convert) | C, migrate to A if it hits the watchdog |
| Index / parse / image / crypto kernels | A (WASM) |
| Author writes Rust/Go/Zig | A |
| Unreviewed third-party distribution | A only (real sandbox) |
| Heavy integration, resident process, broad system access | B (MCP, high trust bar) |
| UI inexpressible in Block Kit | Tier 3 WebView (existing spec) |

Rule of thumb for authors: *"Is your plugin expressible as search box + list + detail + a few actions? → JS track. If not, first ask Atlas for a capability; still no → WASM/MCP."*

### When WASM (Track A) is the right call

1. **Heavy compute** the JS watchdog can't accommodate: fuzzy-search indexing, image processing, OCR, tree-sitter parsing, large diffs, batch hashing. wasmtime fuel/epoch interruption is also more precise than JS interrupts.
2. **Reusing native-ecosystem libraries** compiled to wasm (sqlite-wasm, image codecs, zstd, regex engines) — the legal bypass for the "no native modules" JS limit.
3. **Non-JS authors.**
4. **Fully untrusted code**: QuickJS's sandbox is "the engine exposes no IO" — the engine's own C code is the escape surface. wasmtime provides verified memory isolation with capabilities entering only via explicit imports.

Investment trigger for finishing the WIT bindings (still unbuilt): (a) a real plugin hits the JS watchdog ceiling, or (b) we decide to open unreviewed distribution. Don't pay the WIT bill for imagined demand.

---

## 3. LynxJS evaluation (2026-07-20 deep research)

Question: can ByteDance's Lynx (open-sourced 2025-03) serve as the plugin UI runtime?

**Verdict: no as a dependency; yes as a design reference.** Caveat: fetched from primary sources (lynxjs.org blog/docs, GitHub) but the adversarial-verification pass failed on rate limits; re-verify specifics before load-bearing use.

Findings:

- **Architecture (high confidence, official docs):** dual-thread JS — a *main thread* running PrimJS (QuickJS-derived, ES2019) owns the pixel pipeline (main-thread scripts, layout, render); a *background thread* (default for app code; PrimJS on Android, JSC on iOS) runs component logic. Thread placement is explicit: a literal `"main thread"` directive at the top of a function body.
- **Desktop status:** not in the March-2025 launch (iOS/Android/Web only; GitHub README still lists only those). Lynx 3.7 added macOS/Windows, **but desktop rendering uses Lynx's own self-drawn engine "Clay"** — Flutter-like, *not* native AppKit/Win32 widgets. Desktop embedding = C++17 LynxSDK via CMake (`libLynx.dylib`), no Swift/SwiftUI-level API; the embed guide documents only iOS/Android/HarmonyOS. 2026 roadmap still lists Clay desktop "production-readiness" as future work; the first-party desktop app story is "Lynxtron" — Electron-based, unshipped as of 2026-04.
- **Three disqualifiers as plugin runtime:** (1) not native UI on desktop (Clay self-draws — same reason Flutter was rejected); (2) immaturity — we'd be Clay-on-macOS's biggest user; (3) no untrusted-code model — Lynx is built for embedding *your own* pages (TikTok scenario): no capability grants, no plugin sandbox semantics, plus a C++ toolchain intrusion into a Rust+Swift project.
- **Three things worth stealing:** (1) the dual-thread split maps to our model (plugin logic off-thread, schema patches applied on the UI thread) — and its lesson: latency-sensitive palette paths need a "small host-side logic" slot (v1: host-side optimistic filtering of previous results while awaiting the plugin round-trip) rather than per-keystroke cross-runtime round-trips; (2) PrimJS is production-scale validation that a QuickJS-family engine is sufficient for UI logic — no need for V8/Node; (3) Lynx's element-tree serialization between threads is isomorphic to our schema+patch contract — its open-source element PAPI layer is a reference implementation for schema v1 diff semantics.

---

## 4. Track C — JS plugin runtime design

### 4.1 Engine choice: rquickjs now, PrimJS maybe never

PrimJS repo reality (checked 2026-07-20): gn+ninja build (ByteDance toolchain), C++ 53% + ARM assembly 26% (the template interpreter is hand-written asm — discounted benefit on x86), no Rust bindings, no embedding docs, no QuickJS C-API compatibility promise in the README, 1.1k★. Direct embedding = two weeks feeding a foreign build system for a mobile-ARM-optimized interpreter.

**Decision:** abstract the engine behind a `JsEngine` trait (`eval` / `call` / `interrupt` / `mem_limit`); ship on `rquickjs` (mature QuickJS-NG bindings). Swap to PrimJS only if all three hold: profiling shows the interpreter is the bottleneck on real plugin workloads; target is ARM64; we accept owning the gn build. Palette plugins spend milliseconds of CPU — most likely this never triggers.

### 4.2 Crate layout

```
crates/atlas-plugin-js/
  engine.rs      ← JsEngine trait + rquickjs impl
  sandbox.rs     ← memory/stack limits + CPU watchdog
  host_api.rs    ← capability-gated modules (atlas.ui / clipboard / http / …)
  scheduler.rs   ← one runtime per plugin, tokio blocking-thread pool
```

### 4.3 Isolation model

- **One `JSRuntime` per plugin** (runtimes are ~hundreds of KB; zero shared heap).
- QuickJS has **no built-in IO** — no fs/net/process. Default state is a whitelist sandbox; plugins can only call injected host functions.
- Limits per runtime: memory hard cap (e.g. 32 MB), stack cap, interrupt-handler CPU watchdog (e.g. 200 ms deadline).

```rust
let rt = AsyncRuntime::new()?;
rt.set_memory_limit(32 * 1024 * 1024);
rt.set_max_stack_size(512 * 1024);
rt.set_interrupt_handler(Some(Box::new(move || {
    deadline.elapsed() > Duration::from_millis(200)
})));
```

### 4.4 Capability injection

Manifest declares capabilities; host injects only the declared modules — an undeclared capability's module object simply does not exist. Network/file operations execute on the Rust host side (domain allowlists enforced there); consent UX plugs into the capability flow already designed in the unified spec.

```rust
// manifest: { "capabilities": ["clipboard.read", "http:api.github.com"] }
let atlas = Object::new(ctx)?;
if caps.has("clipboard.read") {
    atlas.set("clipboard", clipboard_module(ctx)?)?;
}
if let Some(hosts) = caps.http_allowlist() {
    atlas.set("http", http_module(ctx, hosts)?)?;
}
ctx.globals().set("atlas", atlas)?;
```

### 4.5 Plugin API shape (deliberately Raycast-adjacent, see §6)

```js
export default {
  onQuery(q)   { return [{ title: q, subtitle: "…", action: "open" }]; }, // background, may be slow
  render(state){ return List([ Item({ title: state.x, onAction: "copy" }) ]); }, // returns schema tree
  onAction(id, payload) { /* … */ },
};
```

Rust receives the schema tree, diffs to a patch, pushes via UniFFI to the platform renderer.

### 4.6 Threading & lifecycle

- Each plugin bound to one blocking thread (reuse the existing shared Tokio `RUNTIME`); events (query/action) queue over a channel.
- Watchdog kills overruns. If the engine's C code itself wedges or crashes, that is in-process risk → **trust tiering** (D7): signed/store plugins run in-process; fully untrusted code stays on the WASM track. JS track = developer-experience track; WASM track = security track.
- Event-driven, short-lived: no resident daemons; background polling only via a host scheduling capability.

### 4.7 Startup: bytecode precompilation

Compile once at install (`JS_WriteObject`), load bytecode at invoke (`JS_ReadObject`) — cold start <5 ms. This is the decisive advantage over Node/Deno subprocesses (100 ms+ cold start) for the invoke-instantly palette scenario.

### 4.8 Track C author-facing limits (documented honestly)

Hard (architectural): component-set-only UI; pure JS only (no N-API/binary npm packages — sharp, better-sqlite3, playwright are all out); no Node stdlib (everything goes through `atlas.*`); event-driven lifecycle (no daemons/long-lived sockets).
Soft (tunable): CPU watchdog; memory cap; http domain allowlist; and the real ceiling — **plugin power = host API coverage**, so ecosystem growth is rate-limited by how fast we ship capability modules (true for Raycast too).

---

## 5. Comparison anchor: how Raycast handles the same constraints

- **UI:** identical constraint — closed component set (`List/Detail/Grid/Form/ActionPanel/MenuBarExtra` + markdown), never opened custom drawing in ten years. Component-set closure demonstrably does not block a 2000+-extension ecosystem.
- **Runtime:** opposite bet — full Node in a child process, zero sandbox (`fs`, `child_process`, unrestricted network). That's why "heavy system" extensions exist without waiting for official APIs. Security is process, not technology: mandatory open source in the `raycast/extensions` monorepo + store review + reputation. Sideloading private extensions is fully exposed.
- **Language:** stricter than us — TypeScript+React only.
- **Runtime cost:** resident warm Node (hundreds of MB) vs our per-plugin few-MB QuickJS runtimes with <5 ms cold start.
- **Lesson:** component closure doesn't limit ecosystems; *system-access freedom is the engine of plugin richness*. Raycast bought it with zero sandbox; capability + trust tiers (D7) buys ~80% of it at far lower risk.

---

## 6. Raycast compatibility strategy

**Precedent (verified 2026-07-20):** Vicinae — C++/Qt/QML cross-platform launcher, 8.5k★, 122 releases (latest 2026-07) — ships "React/TypeScript extensions, compatible with the Raycast ecosystem" plus in-app Raycast store browsing. A third-party compat layer is feasible and is a proven growth lever.

**What full compat requires** (≈ why it's expensive): (1) a Node/Deno subprocess runtime — Raycast extensions lean on Node stdlib + npm deps, QuickJS cannot host them, so compat is a *fourth* track, not an extension of Track C; (2) a `@raycast/api` shim reimplementing components + functions (`showToast`, `Clipboard`, `LocalStorage`, `Cache`, `getPreferenceValues`, `open`, …); (3) a custom React reconciler serializing to our schema (Raycast's component model is nearly isomorphic to Block Kit — translation is mechanical); (4) manifest compat (its `package.json` conventions: commands, preferences, `mode: view/no-view/menu-bar`); (5) service stand-ins (`AI.*` → our LLM channel; `OAuth.PKCEClient` proxy endpoints; `WindowManagement`/`BrowserExtension` → map or no-op).

**Realistic coverage:** ~70–80% (pure API+list extensions). Permanently broken tail: AppleScript/`exec`-dependent, deep Raycast-AI integrations, Swift native extensions. Plus a permanent API-chasing tax — Raycast's API moves monthly.

**Legal:** extensions in `raycast/extensions` are MIT (icons/brand assets excluded). API *surface* imitation is fine (Oracle v. Google); do not copy `@raycast/api` source. "Compatible with Raycast extensions" is nominative fair use; don't use their logo.

**Phasing (D6):**
- **Phase 1 (now, cheap):** shape the native Track C API like `@raycast/api` (naming, props); ship a codemod so porting ≈ changing imports. No Node, no chase tax.
- **Phase 2 (conditional, expensive):** full compat runtime as a **direct-distribution-only** track (unsandboxed Node; App Store channel can't carry it anyway). Trigger: ecosystem cold-start is demonstrably stuck *and* "runs Raycast extensions" is validated as an acquisition lever.
- **Never:** adopting `@raycast/api` as the native API — that hands architectural sovereignty to a competitor's release cadence and assumes Node-full-permission semantics that contradict the capability model.

---

## 7. Delivery order (delta to unified spec §6)

1. **`atlas-ui-schema` crate** (D2) — extract schema definition into Rust core; SwiftUI renderer consumes it. Include patch/diff semantics in schema v1 (full-tree retransmit won't survive live search).
2. **Track C runtime** (`atlas-plugin-js`) — engine trait + rquickjs, sandbox limits, capability injection, bytecode cache.
3. Capability consent UX (shared with Track A, already in unified spec order).
4. Raycast codemod (Phase 1 of D6).
5. WASM WIT bindings — on trigger (§2), unchanged from unified spec.
6. Track D compat runtime — on trigger (§6), direct-distribution only.

Design constraints locked now to avoid rework: schema component set = lowest common denominator natively expressible on all three platforms (platform-specific abilities go through capability declarations, not the core component set); plugin package format is platform-agnostic (manifest + wasm/js + assets + SHA-256 signature, no platform branching in manifests).

---

## 8. References

- Deep-research run 2026-07-20 (Lynx): primary sources lynxjs.org (open-source announcement, 3.7 release, 2026 roadmap, scripting-runtime, embed-lynx-to-native, integrate-with-existing-apps), github.com/lynx-family/lynx; secondary: Callstack dual-thread analysis, Appwrite Lynx-vs-RN. *Verification pass rate-limited — claims are source-extracted but not adversarially verified.*
- github.com/lynx-family/primjs (checked 2026-07-20): gn/ninja, C++/asm, Apache-2.0, 1.1k★, no Rust bindings.
- github.com/vicinaehq/vicinae (checked 2026-07-20): Raycast-compatible launcher precedent.
- [`2026-05-24-plugin-system-design.md`](./2026-05-24-plugin-system-design.md) — Tracks A/B, Block Kit tiers, capability model, distribution.
- [`2026-06-17-modular-distribution-unified.md`](./2026-06-17-modular-distribution-unified.md) — channel split, packaging modes, delivery order this doc amends.
