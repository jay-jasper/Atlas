# Atlas Modular Distribution — Unified Design

**Date:** 2026-06-17
**Status:** Proposed (synthesis spec)
**Supersedes coordination of:** `2026-05-24-dynamic-module-loader-design.md`,
`2026-05-24-plugin-system-design.md`, `2026-05-22-packaging-and-editions-v1.md`
**Audit basis:** `2026-05-24-atlas-roadmap.md` → "Implementation Reality Check (2026-06-17)"

---

## 0. Why this doc exists

Three separate designs each solve one slice of "not every user needs every
component, and nobody wants to download a binary containing all of them":

| Existing design | Slice it owns |
|---|---|
| **Dynamic Module Loader** | *Packaging* — how first-party Rust features are linked/shipped (static vs `.dylib`) |
| **Plugin System** | *Extensibility* — how third-party code (WASM / MCP) extends Atlas |
| **Packaging & Editions** | *Entitlement* — who is *allowed* to run a component (Free/Pro/Community) |

None of them, alone, answers the product question end-to-end. This spec stitches
them into **one model** and reconciles it with the two hard external constraints
the user named: **shipping on both the Mac App Store and direct distribution**,
and **four motivations** (download size, UI clutter, paid tiers, third-party
plugins). It does not redesign the internals — it defines how the three layers
compose, which combinations are legal per channel, and the order to build them.

---

## 1. The hard constraint that forces the whole shape

**The Mac App Store forbids downloading and executing code that wasn't in the
reviewed bundle.** Direct distribution (notarized DMG + a Sparkle-style updater)
allows it. That single fact splits the four motivations by channel:

| Motivation | App Store edition | Direct edition |
|---|---|---|
| **Download/install size** | ⚠️ Limited — everything ships in the bundle; App Thinning is marginal | ✅ Real on-demand download |
| **UI not cluttered** | ✅ Runtime gating hides disabled modules | ✅ Same |
| **Paid tiers** | ✅ StoreKit IAP unlocks a runtime entitlement | ✅ Own license / server entitlement |
| **Third-party plugins** | ❌ Impossible — no external executable code | ✅ WASM/MCP sandboxed plugins |

**Conclusion baked into the architecture:** *download-size savings* and
*third-party plugins* are **direct-edition-only** capabilities. Do not try to
satisfy them on the App Store build — instead, build **one modular codebase**
that **feature-detects its capabilities at runtime** and ships in **two
packaging modes** off the same module abstraction.

---

## 2. Unified layered model

One registration model, four trust tiers, two packaging modes layered on top.

```
┌──────────────────────────────────────────────────────────────────────┐
│  Atlas.app (SwiftUI MenuBarExtra)                                     │
│  • Module Center UI  • Edition/Entitlement gate  • Block Kit renderer │
├──────────────────────────────────────────────────────────────────────┤
│  atlas-ffi (UniFFI)  — stable façade: list_modules / set_enabled /    │
│                        dispatch_module(id, cmd, payload)              │
├──────────────────────────────────────────────────────────────────────┤
│  KERNEL = atlas-core (slim)                                          │
│   FeatureManager · ModuleRegistry · ModuleLoader · EntitlementGate   │
│   shared models · single Tokio runtime                               │
├───────────────┬───────────────────────┬──────────────────────────────┤
│  TIER 1        │  TIER 2               │  TIER 3                      │
│  Kernel        │  First-party modules  │  Third-party plugins        │
│  (always in)   │  (trusted Rust)       │  (sandboxed)                │
│                │  C-ABI .dylib OR      │  WASM (wasmtime) / MCP      │
│                │  static-linked        │  (subprocess)               │
│                │  ← Dynamic Loader doc │  ← Plugin System doc        │
└───────────────┴───────────────────────┴──────────────────────────────┘
                         ▲
        EntitlementGate (Editions doc) cross-cuts Tier 2 + Tier 3:
        is_entitled(module_id) checked before load/enable, in BOTH modes.
```

Key unifications over the three source docs:

1. **One registry, two runtimes of trust.** First-party `.dylib` modules and
   third-party WASM/MCP plugins both register through the *same* `ModuleRegistry`
   façade (per the loader doc §1.2 and plugin doc §9), but first-party runs
   in-process with full Rust capability while plugins run sandboxed +
   capability-gated. The Swift UI (Module Center) lists both from one manifest.
2. **The EntitlementGate is the single chokepoint.** Both the loader's
   `enable()` and the plugin host's install/enable funnel through
   `is_entitled(id)`. The Editions doc currently gates only Swift-side UI; this
   spec moves the gate *down into the kernel registry* so it applies to dynamic
   loading too (loader doc §10 "Editions × Modules" open question — resolved
   here).
3. **One manifest schema** drives Module Center for first-party (`module.toml`)
   and third-party (`plugin.toml`) alike: id, display name, size, version,
   `abi_version`/`api_version`, required permissions, **entitlement id**, and
   **download URL (direct edition only)**.

---

## 3. Two packaging modes off one module set

The same `atlas-module-*` crates compile two ways. The build flavor — not the
source — decides the mode.

### Mode A — Static link (App Store build + a "Full" direct build)

- Modules pulled in at compile time via Cargo features; registered through
  `inventory`/`linkme` so the registry is populated without `dlopen`.
- Locked/disabled modules are **present in the binary but gated** by
  `EntitlementGate` + `FeatureManager` → their SwiftUI panels never render
  (solves *UI clutter*; does **not** save size).
- Paid tiers: **StoreKit IAP** flips a local entitlement that the gate reads.
- Third-party plugins: **WASM/MCP disabled** in this mode (App Store rule).

### Mode B — Dynamic + on-demand (direct edition only)

- Each module is a signed `*.atlasmodule/` (`module.toml` + `lib*.dylib`),
  discovered and `dlopen`'d only when enabled (loader doc §5). Disabled ⇒ not
  loaded ⇒ no allocations, no background tasks, **no permission prompt**.
- v1 ships every module inside the bundle (real win already: a Free user who
  declines Capture never triggers Screen Recording permission). **v2 downloads**
  new `*.atlasmodule` packages from the Hub into
  `~/Library/Application Support/Atlas/Modules/` (loader doc §10) — this is the
  step that delivers *true download-size savings*.
- Third-party WASM/MCP plugins available; capability-gated (plugin doc §7).
- Paid tiers: own license key / server entitlement feeding the same gate.

```
Capability matrix the app feature-detects at launch:

                       Mode A (App Store)   Mode B (Direct)
 dynamic dylib load          no                  yes
 remote module download      no                  yes (v2)
 third-party WASM/MCP        no                  yes
 runtime UI gating           yes                 yes
 paid-tier unlock           StoreKit IAP    license/server
```

The Swift `EntitlementService` (already built) gains a sibling
`DistributionCapabilities` provider so panels/Module-Center adapt to the running
mode without per-build `#if` forks beyond the entitlement source.

---

## 4. Reconciling each motivation, end to end

- **Download/install size.** Solved by **Mode B + dynamic loader + Hub download
  (v2)**. Prerequisite that does not exist yet: the loader itself (audit: no
  `libloading`/`ModuleRegistry`). *Reality check:* Rust feature crates are
  typically small; the size argument only pays off for heavy modules (whisper
  model, large frameworks). Package those as **separately downloadable** in Mode
  B; keep light modules static even in the direct build.
- **UI not cluttered.** Solved **today** by runtime gating in both modes
  (`FeatureManager` + `EntitlementService` already wired). No loader needed.
- **Paid tiers.** Gating logic **exists** (`EditionModels`/`EntitlementService`).
  Missing: **StoreKit IAP** (App Store) and a **license/server** path (direct).
  Both feed the existing gate — additive, no rework.
- **Third-party plugins.** **Direct-only.** Foundation **exists** (real wasmtime
  exec, real MCP stdio, Block Kit schema). Missing: WIT typed bindings, install
  CLI/Hub fetch, capability-consent UI.

---

## 5. Current status vs design (from the 2026-06-17 audit)

| Layer | Designed in | Built? |
|---|---|---|
| Runtime feature gating | features/editions | ✅ wired (FFI live, `EntitlementService`) |
| Editions metadata + local entitlement | Editions doc | ✅ wired, **local-only** |
| StoreKit IAP / license-server unlock | (this spec) | ❌ not built |
| Dynamic `.dylib` loader, ModuleRegistry, vtable, C-ABI | Loader doc | ❌ design-only |
| First-party modules as separate crates | Loader doc §3 | ❌ still static in `atlas-core` |
| Hub index parse + SHA-256 verify | Plugin/Hub | ✅ real (`hub.rs`) |
| Hub HTTP download transport | Loader §10 / Plugin §8 | ❌ not built |
| WASM execution host | Plugin doc §4 | ✅ real (`wasm_host.rs`, wasmtime 26) |
| WIT Component Model bindings | Plugin doc §4.2 | ❌ absent (core-wasm ABI only) |
| MCP client + stdio transport | Plugin doc §5 | ✅ real (`mcp.rs`, `mcp_transport.rs`) |
| Block Kit schema + SwiftUI renderer | Plugin doc §3 | ✅ schema real; renderer present |
| Capability consent / enforcement UI | Plugin doc §7 | ⚠️ enforcement logic exists; consent UX TBD |
| Embedded Lua (Hammerspoon bridge) | #55 | ✅ real (`mlua`) |

**The single highest-leverage missing piece is the dynamic module loader** — it
is the prerequisite for download-size savings *and* the shared registration spine
for first-party + third-party. Everything else is either done or additive.

---

## 6. Recommended delivery order

Sequenced so each step ships value independently and de-risks the next. Channel
applicability noted.

1. **Entitlement gate → kernel (both channels).** Move `is_entitled(id)` from
   Swift-only into `ModuleRegistry`/`FeatureManager` so it governs loading, not
   just UI. *Unblocks consistent gating before the loader lands.* — small.
2. **StoreKit IAP unlock (App Store).** Wire a `StoreKitEntitlementProvider`
   into the existing `EntitlementProviding` seam. Delivers *paid tiers* on the
   App Store with no architecture change. — small/medium.
3. **Dynamic module loader, v1 bundled (direct).** Execute the Loader doc
   Phases α–γ: kernel split, `atlas-module-sdk` + C-ABI vtable, migrate
   `capture` + `monitor` to `.dylib`, bundle in `Frameworks/AtlasModules/`.
   Delivers *no-permission-until-enabled* + smaller resident memory. — large
   (loader doc estimate 9–11 wks for the four-module set).
4. **Hub HTTP download transport, v2 (direct).** Add the fetch transport behind
   the existing SHA-256 verify; download `*.atlasmodule` packages on demand.
   Delivers *true download-size savings*. — medium; depends on (3).
5. **Plugin WIT bindings + install/consent UX (direct).** Finish Track A typed
   bindings and the capability-consent flow on top of the real wasmtime/MCP
   hosts. Delivers *third-party plugins*. — medium/large; independent of (3)/(4).

App Store editions get value from steps 1–2 (gating + paid tiers) and remain on
Mode A. Direct editions layer 3–5 to unlock size + plugins.

---

## 7. Open questions inherited / resolved

- **Editions × dynamic modules** (loader §10, editions safety notes): *resolved*
  — gate lives in the kernel registry; Free edition may ship a dylib on disk but
  the gate refuses `enable()`. Omit-at-packaging is a per-module size
  optimization for Mode B only.
- **Two runtimes / Tokio across dylib boundary** (loader §12): unchanged — one
  kernel runtime, modules receive a `RuntimeHandle` via `HostContext`.
- **Plugin monetization** (plugin doc §11 out-of-scope): stays out of scope; the
  EntitlementGate covers first-party paid tiers only for now.
- **Signing for v2 remote modules** (loader §10): still open — sign-by-Atlas vs
  sign-by-author. Decide once the v1 ABI is proven.

---

## 8. References

- `2026-05-24-dynamic-module-loader-design.md` — Tier 2 packaging mechanics
- `2026-05-24-plugin-system-design.md` — Tier 3 extensibility (WASM/MCP/Block Kit)
- `2026-05-22-packaging-and-editions-v1.md` — entitlement layer (built, local-only)
- `2026-05-24-atlas-roadmap.md` §"Implementation Reality Check" — ground-truth status
