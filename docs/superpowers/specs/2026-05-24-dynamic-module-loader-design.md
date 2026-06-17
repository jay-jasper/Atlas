# Atlas Dynamic Module Loader — Architecture Design

**Date:** 2026-05-24
**Status:** Approved (design phase) — **NOT YET BUILT** as of 2026-06-17 audit (no `libloading`/`ModuleRegistry`/vtable in code; features remain static in `atlas-core`). This is the gating prerequisite for download-size savings.
**Scope:** Convert first-party functionality from compile-time members of `atlas-core` into independently shipped dynamic libraries (`.dylib`) discovered and loaded at runtime by a small kernel. Goal is install-time and runtime footprint reduction without changing UX.
**Unified context:** This doc owns the **Tier 2 packaging** slice. See [`2026-06-17-modular-distribution-unified.md`](./2026-06-17-modular-distribution-unified.md) for how it composes with the plugin system, editions, and the App-Store-vs-direct channel split.

---

## 1. Motivation

### 1.1 Where the weight sits today

`atlas-core` statically links every domain: capture, monitor, port master, sensors, battery, disk. Planned domains (translation, clipboard/scratchpad, workspaces, GIF recording, scrolling capture, …) are slated for the same crate. The result:

- A binary that grows with every feature the team adds, whether or not the user wants it.
- `FeatureManager` toggles control runtime *execution* but not *linkage* — disabled features still occupy memory, still pull their transitive deps into the binary, and still trigger macOS permission prompts (screen recording, accessibility) the first time related code paths initialize subsystems.
- Editions (Free / Pro / Community) currently described in `packaging-and-editions-v1` are evaluated locally on top of the same monolith; turning a feature "off for Free" hides UI but ships the code.

### 1.2 What we want

- **Kernel binary < 15 MB** (currently growing past this with sensors + battery already in).
- **Disabled module ⇒ not loaded** — no allocations, no background tasks, no permission surface.
- A clear extension boundary so first-party modules and third-party plugins (from `2026-05-24-plugin-system-design.md`) share a single registration model.
- A migration path that does **not** require rewriting working code: the four existing/planned domains move out of `atlas-core` with their internals intact.

### 1.3 What this is not

- Not a remote installer. v1 ships every first-party module inside the app bundle. Remote download is a deliberate v2 (Section 10).
- Not the plugin system. Plugins are sandboxed and capability-gated; first-party modules are trusted code and run in-process with full Rust capability. They share the **registry**, not the **runtime**.
- Not an Editions replacement. Editions stay as the commercial/availability layer; this design changes how features are *packaged*, not who is *entitled* to them.

---

## 2. Layered Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Atlas.app (SwiftUI MenuBarExtra)                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  atlas-ffi (UniFFI bridge)                            │  │
│  │  Stable façade: AtlasCore, ModuleRegistry, ...        │  │
│  └───────────────────────────────────────────────────────┘  │
│                          ↕                                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Kernel = atlas-core (slim)                           │  │
│  │   • FeatureManager  (existing, retained)              │  │
│  │   • ModuleRegistry  (new — vtable-keyed dispatch)     │  │
│  │   • ModuleLoader    (new — libloading + ABI guard)    │  │
│  │   • Shared models   (SystemSnapshot, capture types…)  │  │
│  │   • Shared runtime  (single Tokio runtime handle)     │  │
│  └───────────────────────────────────────────────────────┘  │
│                          ↕  C ABI vtable                    │
│  ┌──────────┬──────────┬───────────────┬─────────────────┐  │
│  │ capture  │ monitor  │ translation   │ clipboard       │  │
│  │ .dylib   │ .dylib   │ .dylib        │ .dylib          │  │
│  └──────────┴──────────┴───────────────┴─────────────────┘  │
│                          ↕  WASM / MCP (separate path)      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Third-party Plugins (atlas-plugin-host, separate)    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

Three layers, in order of trust:

1. **Kernel** — always loaded, ships in the main binary. Owns process state, UI bridge, registries, single Tokio runtime.
2. **First-party module** — trusted Rust code, distributed as a signed `.dylib` inside the app bundle (v1) or downloadable (v2). C ABI to the kernel. No sandbox.
3. **Plugin** — third-party code in WASM or MCP. Designed separately; registers through the same `ModuleRegistry` façade but runs under the plugin host's capability gating.

---

## 3. Crate Reorganization

### 3.1 Target layout

```
crates/
├── atlas-core/                  # Kernel — was the monolith, now slim
│   ├── src/
│   │   ├── lib.rs
│   │   ├── features.rs          # existing FeatureManager (retained)
│   │   ├── module/
│   │   │   ├── mod.rs
│   │   │   ├── registry.rs      # ModuleRegistry
│   │   │   ├── loader.rs        # libloading + ABI guard
│   │   │   ├── vtable.rs        # repr(C) vtable definitions
│   │   │   └── abi.rs           # version constants, panic boundary
│   │   ├── runtime.rs           # shared Tokio runtime handle
│   │   └── models/              # shared structs (moved from monitor/models.rs etc.)
│   └── Cargo.toml
│
├── atlas-module-sdk/            # NEW — what modules depend on
│   ├── src/lib.rs               # re-exports: vtable types, models, runtime handle type
│   └── Cargo.toml               # no_std-leaning; minimal deps
│
├── atlas-module-capture/        # was crates/atlas-core/src/capture/
│   ├── src/
│   │   ├── lib.rs               # exports atlas_module_entry
│   │   └── engine.rs            # unchanged internals
│   └── Cargo.toml               # crate-type = ["cdylib"]
│
├── atlas-module-monitor/        # was crates/atlas-core/src/monitor/
│   ├── src/
│   │   ├── lib.rs               # exports atlas_module_entry
│   │   ├── collector.rs
│   │   ├── battery.rs
│   │   ├── sensors.rs
│   │   ├── disk.rs
│   │   └── port_master.rs
│   └── Cargo.toml               # crate-type = ["cdylib"]
│
├── atlas-module-translation/    # NEW — has no current implementation
│   └── …                        # built directly into module shape
│
├── atlas-module-clipboard/      # NEW — has no current implementation
│   └── …                        # includes scratchpad
│
└── atlas-ffi/                   # UniFFI bridge — surface stays stable
    └── …                        # internally talks to ModuleRegistry
```

### 3.2 Migration scope per crate

| Crate | Current state | v1 action |
|---|---|---|
| `atlas-core` | Monolith (capture + monitor + features) | Strip capture/* and monitor/* out; add `module/*`, `runtime.rs`, move shared models to `models/` |
| `atlas-module-sdk` | Does not exist | Create. Shared ABI types only. |
| `atlas-module-capture` | Lives at `atlas-core/src/capture/` | New crate, sources moved verbatim, add `lib.rs` entry export |
| `atlas-module-monitor` | Lives at `atlas-core/src/monitor/` | Same as capture |
| `atlas-module-translation` | Plan only (`translation-engine-v1`) | Implement directly into the new module shape — do not detour through `atlas-core` |
| `atlas-module-clipboard` | Plan only (`clipboard-history-v1`, `scratchpad-v1`) | Same as translation |
| `atlas-ffi` | Talks to `AtlasCore` singleton | Façade unchanged externally; internally routes through `ModuleRegistry` |

### 3.3 What stays in `atlas-core`

Anything every module needs to share or that owns process state:

- `FeatureManager` (existing toggle store; now also indicates which modules to *load*).
- `ModuleRegistry` — keyed by module ID, holds vtable + handle to loaded `Library`.
- Shared models (`SystemSnapshot`, `PortProcessInfo`, capture image types) — moved into `atlas-core::models`. Modules see these via `atlas-module-sdk` re-exports.
- The single Tokio `Runtime`. Modules never construct their own; they receive a `RuntimeHandle` through the vtable.

---

## 4. The C ABI

This is the highest-risk surface in the design. The rules below are non-negotiable.

### 4.1 ABI version

```rust
// atlas-module-sdk/src/lib.rs
pub const ATLAS_MODULE_ABI_VERSION: u32 = 1;
```

Every module exports this constant. Loader rejects mismatches before invoking anything else. Bump on any breaking vtable change. Additive fields use a versioned vtable struct (Section 4.4).

### 4.2 Entry point

Each `.dylib` exports exactly one symbol:

```rust
// in every atlas-module-* crate
#[no_mangle]
pub extern "C" fn atlas_module_entry() -> *const ModuleVTable {
    &MODULE_VTABLE
}
```

Returning a pointer to a `'static` vtable (not a heap allocation) avoids ownership questions across the boundary. The vtable lives in the module's data segment for the lifetime of the loaded library.

### 4.3 The vtable

```rust
// atlas-module-sdk/src/vtable.rs
#[repr(C)]
pub struct ModuleVTable {
    /// ABI version this module was built against. Must equal ATLAS_MODULE_ABI_VERSION.
    pub abi_version: u32,

    /// Module identity. Static strings owned by the module.
    pub metadata: ModuleMetadata,

    /// Lifecycle.
    pub init:     unsafe extern "C" fn(ctx: *const HostContext) -> ModuleResult,
    pub start:    unsafe extern "C" fn(handle: *mut ModuleHandle) -> ModuleResult,
    pub stop:     unsafe extern "C" fn(handle: *mut ModuleHandle) -> ModuleResult,
    pub shutdown: unsafe extern "C" fn(handle: *mut ModuleHandle),

    /// Command dispatch. Modules respond to typed commands routed by the kernel.
    /// payload + reply are length-prefixed CBOR buffers, allocated and freed via host allocators.
    pub dispatch: unsafe extern "C" fn(
        handle:  *mut ModuleHandle,
        command: ModuleCommandId,
        payload: AtlasBuffer,
        reply:   *mut AtlasBuffer,
    ) -> ModuleResult,

    /// Free a buffer the module allocated and handed to the host.
    pub free_buffer: unsafe extern "C" fn(buf: AtlasBuffer),
}

#[repr(C)]
pub struct ModuleMetadata {
    pub id:           AtlasStr,   // static, e.g. "capture"
    pub display_name: AtlasStr,
    pub version:      AtlasStr,
    pub capabilities: AtlasCapabilityBits,
}
```

Notes:

- `unsafe extern "C"` everywhere — the boundary is FFI, not Rust calling Rust.
- `ModuleHandle` is opaque to the kernel. The module creates it in `init`, the kernel holds the pointer and passes it back on every call.
- `HostContext` carries pointers the module needs from the kernel (runtime handle, logger, storage path). Section 4.6.

### 4.4 Extending the vtable

Adding optional capability later (e.g., a `render_block_kit` hook for modules that want to participate in plugin-style UI): append to a *separate* `ModuleVTableV2` struct and dispatch by version. Never reorder, repurpose, or remove fields in `ModuleVTableV1`. The loader stores the version it observed and only calls fields valid for that version.

### 4.5 Memory ownership across the boundary

The single most error-prone area. Rule: **whoever allocates, frees.** Always via explicit free functions.

```rust
#[repr(C)]
pub struct AtlasBuffer {
    pub ptr: *mut u8,
    pub len: usize,
    pub cap: usize,        // for Vec round-trip
    pub owner: BufferOwner // Host | Module
}

#[repr(u8)]
pub enum BufferOwner { Host, Module }
```

- Host → Module: kernel allocates `AtlasBuffer { owner: Host }`, passes it in, kernel frees after the call returns.
- Module → Host: module allocates `AtlasBuffer { owner: Module }`, writes pointer into the out-param, kernel later calls `vtable.free_buffer(buf)` to release.
- No raw Rust `String`, `Vec`, `Box<T>` crosses the boundary. They always wrap into `AtlasBuffer` / `AtlasStr` (`AtlasStr` is just a `*const u8 + len` slice borrowed from static module memory).
- Payloads use **CBOR** (`ciborium`). JSON considered and rejected: CBOR is faster, smaller, and handles binary frames (capture PNGs) without base64.

### 4.6 HostContext

```rust
#[repr(C)]
pub struct HostContext {
    /// Tokio runtime handle. Modules schedule async work via spawn_on_runtime fn ptr.
    pub spawn_on_runtime: unsafe extern "C" fn(task: AtlasTask),

    /// Structured logging into the host's tracing subscriber.
    pub log: unsafe extern "C" fn(level: u8, target: AtlasStr, message: AtlasStr),

    /// Per-module persistent storage directory (already created by host).
    pub storage_dir: AtlasStr,

    /// Callback to notify the host of asynchronous events
    /// (e.g., monitor pushing a SystemSnapshot every second).
    pub emit_event: unsafe extern "C" fn(module: AtlasStr, event: AtlasBuffer),
}
```

Critical: modules never call `tokio::runtime::Runtime::new()`. There is exactly one runtime in the process — the kernel's. Modules submit work via `spawn_on_runtime`. This is the single most common source of crashes when loading async-heavy Rust code across `dylib` boundaries, and the design specifically forbids it.

### 4.7 Panic boundary

Every `extern "C" fn` in the vtable wraps its body in `std::panic::catch_unwind`. A panic returns `ModuleResult::Panicked` and the kernel marks the module dead — no second invocation, no cleanup call into the module (its state is presumed corrupt). The kernel then emits a notification and the user can choose to reload the module from settings.

```rust
unsafe extern "C" fn capture_init(ctx: *const HostContext) -> ModuleResult {
    catch_unwind(AssertUnwindSafe(|| init_impl(ctx)))
        .unwrap_or(ModuleResult::Panicked)
}
```

### 4.8 Build settings (all modules)

```toml
[lib]
crate-type = ["cdylib"]

[profile.release]
panic = "unwind"        # catch_unwind only works with unwind, not abort
codegen-units = 1
lto = "thin"
strip = "symbols"
```

`panic = "abort"` is incompatible with the panic boundary above. All modules and the kernel must agree.

---

## 5. Loading Protocol

### 5.1 Discovery

```
Atlas.app/Contents/Frameworks/AtlasModules/
├── capture.atlasmodule/
│   ├── module.toml          # metadata, capabilities, abi_version expected
│   └── libcapture.dylib
├── monitor.atlasmodule/
│   ├── module.toml
│   └── libmonitor.dylib
├── translation.atlasmodule/
└── clipboard.atlasmodule/
```

`module.toml` is parsed *before* dlopen. If a module is disabled in `FeatureManager`, the loader skips it entirely — no `Library::new`, no permission prompts.

```toml
# capture.atlasmodule/module.toml
id = "capture"
display_name = "Screen Capture"
version = "0.1.0"
abi_version = 1
dylib = "libcapture.dylib"
default_enabled = true
permissions = ["screen-recording"]
```

### 5.2 Load sequence

```
1. Read module.toml.
2. Check feature_manager.is_enabled(id). If false → skip.
3. libloading::Library::new(path).
4. Library::get::<unsafe extern "C" fn() -> *const ModuleVTable>(b"atlas_module_entry").
5. Read vtable.abi_version. If != ATLAS_MODULE_ABI_VERSION → unload, log, skip.
6. Validate vtable.metadata.id matches module.toml id.
7. registry.insert(id, LoadedModule { library, vtable_ptr, handle: None }).
8. Call vtable.init(host_context). On Ok, allocate ModuleHandle, store it.
9. Call vtable.start(handle). Module is now live.
```

Each step is fallible and isolated: a failure at step 5 unloads the library and continues with the next module. One bad module never blocks the kernel from starting.

### 5.3 Unload sequence

```
1. registry.get_mut(id).
2. Call vtable.stop(handle).
3. Call vtable.shutdown(handle).       // module drops its state
4. Drop the libloading::Library.       // dlclose
5. Remove from registry.
```

`dlclose` on macOS does **not** guarantee the dylib is unmapped — the OS may keep it cached. This is acceptable. What we guarantee is no further calls reach the module's code.

### 5.4 Crash isolation

`catch_unwind` (Section 4.7) handles Rust panics. Hard segfaults inside a module crash the whole process — same as any in-process plugin model. Mitigation:

- v1: process-wide crash, restart with the offending module disabled (the kernel persists a "last loaded module" breadcrumb and auto-disables on relaunch after crash).
- v2+: out-of-process host for modules flagged as unstable (mirrors the MCP plugin track).

---

## 6. Module Lifecycle

```
                ┌──────────┐
                │ Unloaded │
                └────┬─────┘
       enable()      │
                     ▼
                ┌──────────┐
                │  Loaded  │  ← library mmap'd, vtable read, abi checked
                └────┬─────┘
              init() │
                     ▼
                ┌──────────┐
                │   Init   │  ← module owns handle, no work yet
                └────┬─────┘
             start() │
                     ▼
                ┌──────────┐
                │ Running  │  ← dispatch() and events flow
                └────┬─────┘
              stop() │
                     ▼
                ┌──────────┐
                │ Stopped  │  ← background tasks halted, handle alive
                └────┬─────┘
          shutdown() │
                     ▼
                ┌──────────┐
                │ Unloaded │
                └──────────┘
```

`init` is cheap (allocate structs, no I/O, no threads). `start` is where the module may spawn tasks, open files, request permissions. `stop` halts work but keeps state — used for "pause module without losing in-memory data" (e.g., the user toggles clipboard history off briefly).

---

## 7. Kernel-Facing API

### 7.1 Registry

```rust
// atlas-core/src/module/registry.rs
pub struct ModuleRegistry {
    modules: RwLock<HashMap<ModuleId, LoadedModule>>,
}

impl ModuleRegistry {
    pub fn load_all(&self, modules_dir: &Path, features: &FeatureManager) -> LoadReport;
    pub fn dispatch(&self, id: &ModuleId, cmd: ModuleCommandId, payload: &[u8]) -> Result<Vec<u8>>;
    pub fn enable(&self, id: &ModuleId) -> Result<()>;
    pub fn disable(&self, id: &ModuleId) -> Result<()>;
    pub fn list(&self) -> Vec<ModuleStatus>;
}
```

### 7.2 FFI surface (atlas-ffi)

The UDL stays small. We do *not* expose one UniFFI function per module command — Swift talks to the registry by command ID + CBOR payload:

```idl
// crates/atlas-ffi/src/atlas.udl  (additions)
interface AtlasCore {
    sequence<ModuleStatus> list_modules();
    void set_module_enabled(string id, boolean enabled);
    bytes dispatch_module(string id, u32 command, bytes payload);
};
```

UniFFI-level type safety is preserved by adding thin Swift wrappers per command on the Swift side, but the FFI surface itself doesn't grow when we add a module. This is deliberate — every new module would otherwise force a UDL change + UniFFI regen + Xcode project update.

### 7.3 What the existing UDL functions do

Existing functions (`take_screenshot`, `start_monitoring`, etc.) are kept as thin façades during the migration:

```rust
pub fn take_screenshot() -> Result<Vec<u8>, AtlasError> {
    let reply = REGISTRY.dispatch(&"capture".into(), commands::TAKE_FULL_SCREEN, &[])?;
    Ok(reply)
}
```

This keeps the Swift app working unchanged during the migration. Phase γ (Section 9) is when Swift starts using the generic `dispatch_module` directly.

---

## 8. Packaging (v1: bundled, all included)

### 8.1 Xcode integration

A new build phase in `Atlas.xcodeproj`:

```
"Build Atlas Modules" (Run Script, before Compile Sources)
└── runs: scripts/build-modules.sh ${CONFIGURATION}
        produces: target/{debug,release}/lib{capture,monitor,translation,clipboard}.dylib

"Copy Atlas Modules" (Copy Files, destination: Frameworks)
└── packs each dylib + its module.toml into a *.atlasmodule directory
    under Atlas.app/Contents/Frameworks/AtlasModules/
```

### 8.2 Code signing

Each `.dylib` must be signed with the same identity as the app and have the Hardened Runtime enabled. The build phase invokes `codesign --force --options=runtime --sign "$EXPANDED_CODE_SIGN_IDENTITY"` per dylib before they are copied. Notarization stays a single submission for the whole `.app`.

### 8.3 First-launch experience (v1 — local)

Because every dylib is already on disk, "install" is just toggling on the feature. The Onboarding flow:

1. Asks the user which categories they care about (Capture / Monitor / Translation / Clipboard).
2. Sets `FeatureManager` accordingly. Unchecked modules stay on disk but are never `dlopen`'d.
3. No permission prompts fire until the module is actually loaded — so a user who declines Capture never sees the Screen Recording permission dialog.

This is the meaningful win at v1 even without remote download: a Free-edition user who only wants the menu bar and monitor never loads three other dylibs into memory, never triggers their permission surface, and never pays for their startup tasks.

---

## 9. Implementation Phases

### Phase α — Kernel split (2 weeks)
- Carve `module/`, `runtime.rs`, `models/` into `atlas-core`.
- Create `atlas-module-sdk` with the v1 vtable.
- Loader works against a hand-written stub `.dylib` in tests.
- `atlas-ffi` unchanged.

### Phase β — Capture module migration (1 week)
- Move `capture/` into `atlas-module-capture`.
- Wire the existing UDL `take_screenshot` through the registry façade.
- macOS bundle build phase copies the `.dylib` into `Frameworks/AtlasModules/`.
- Acceptance: screenshot still works end-to-end; binary size of main app drops by ~size of `screenshots` + `image` deps.

### Phase γ — Monitor module migration (1 week)
- Same playbook for `monitor/`.
- Validate the event-callback path: monitor pushes `SystemSnapshot` via `emit_event`, kernel forwards to the existing `SystemMonitorCallback`.
- Acceptance: disabling the monitor module means no Tokio task, no `sysinfo` polling, no `lsof` shell-outs in the process.

### Phase δ — New modules built native (3-4 weeks)
- Translation and Clipboard implemented directly into the module shape (no detour through `atlas-core`).
- This is the validation of the developer experience: new features land as separate crates from day one.

### Phase ε — Generic Swift bridge (1-2 weeks)
- Swift moves from per-command UDL functions to `dispatch_module(id, cmd, payload)`.
- The four legacy façades in `atlas-ffi` are kept for one release, then removed.

### Phase ζ — Crash recovery + observability (1 week)
- Persisted "last loaded module" breadcrumb for auto-disable on relaunch.
- `atlas modules status` CLI subcommand for diagnostics.

**Total estimate:** 9-11 weeks to fully migrate the four-module set with no UX regression.

---

## 10. v2 Remote Distribution (out of scope, design hooks only)

The v1 design intentionally leaves room for these without requiring rework:

- `module.toml` already carries `version` and `abi_version`. A remote registry can advertise these.
- The loader already treats `AtlasModules/` as a directory of self-contained `*.atlasmodule` packages. v2 just downloads new packages into the same directory under `~/Library/Application Support/Atlas/Modules/`.
- The signing story is the open question for v2 (sign-by-Atlas-team vs sign-by-author vs unsigned-with-warning). Defer until v1 ABI is proven stable.
- Editions logic stays where it is — the entitlement service simply checks which modules a given edition is allowed to load.

---

## 11. Testing Strategy

### 11.1 Per-module
Each module crate keeps its existing `cargo test` suite. Internal correctness does not need the loader.

### 11.2 ABI integration tests
A new test crate `atlas-module-loader-tests` produces a tiny fixture module (`crates/test-fixtures/echo-module/`) that exports the vtable, and the test:

1. Builds the fixture as `cdylib`.
2. Loads it through `ModuleRegistry::load_all`.
3. Exercises every lifecycle transition.
4. Dispatches a known command and asserts the round-trip.
5. Sends a poisoned payload to verify `catch_unwind` returns `Panicked` instead of aborting.

### 11.3 Crash isolation tests
A second fixture (`crash-module`) deliberately panics in `dispatch`. The test asserts:

- Kernel survives the panic.
- The module is marked dead in the registry.
- Subsequent `dispatch` calls return `ModuleNotAvailable` without re-entering module code.

### 11.4 Bundle sanity
A scripted check in CI: after building the `.app`, verify each `*.atlasmodule` is present, signed, and contains a `dylib` whose `atlas_module_entry` symbol resolves.

---

## 12. Risks and Trade-offs

| Risk | Severity | Mitigation |
|---|---|---|
| Rust types accidentally crossing the FFI boundary as Rust types (`String`, `Vec`) instead of `AtlasBuffer` | High | `atlas-module-sdk` provides only `repr(C)` types. The kernel's vtable struct refuses to compile if a field's type isn't repr-C-safe. Clippy lint added: `clippy::exhaustive_structs` on all vtable types. |
| Two Tokio runtimes (one per dylib) causing deadlocks | High | Modules never construct a runtime. `tokio::runtime::Handle` flows in via `HostContext`. Lint: ban `Runtime::new()` in module crates via `clippy::disallowed_methods` config. |
| `dlclose` not actually unmapping on macOS | Medium | Documented behavior. Treat unload as "stop calling," not "reclaim memory." Reload-after-update requires app restart in v1. |
| `panic = "abort"` accidentally enabled in a module profile | High | Workspace-level `[profile.release]` enforces `unwind`. CI checks the compiled dylib for the panic strategy. |
| ABI drift between kernel and modules at runtime (user updates one but not the other) | Medium | `abi_version` check at load. Modules with mismatched version refuse to load and surface a clear error in the Feature Center. v1 sidesteps this because all dylibs ship together; v2 must handle it. |
| Symbol collisions between modules (e.g., two crates linking `image` differently) | Medium | Each module is its own `cdylib` with its own static archive. No symbols are shared except the explicitly `#[no_mangle]` entry point. Verified with `nm` in the bundle sanity test. |
| First-class modules drift away from the plugin UI model | Low | Modules ignore Block Kit in v1 — they have their own SwiftUI panels. If we later want unified rendering, the vtable extension path (Section 4.4) covers it. |
| Increased developer friction (every new feature is its own crate) | Medium | Document a `cargo generate` template for new modules. Phase δ tests this in practice. |

---

## 13. Open Questions

1. **Hot reload during development.** Worth supporting? Would require teardown + dlclose + dlopen on every `cargo build` in the module crate. Defer to Phase ζ at earliest.
2. **Per-module logging granularity.** Today `tracing` filters are process-global. Per-module log levels are easy to add via `HostContext.log` filtering — confirm UX value before building.
3. **Module-to-module dependencies.** Can Clipboard call into Capture? v1: no, kernel mediates. Revisit when a concrete need emerges (e.g., scrolling capture wanting to stash frames into clipboard).
4. **Test runtime.** Should the ABI test fixtures live inside this repo or a separate one? Inside is simpler; separate enforces the boundary harder.
5. **Editions × Modules surface.** Free edition may include the dylib on disk but disallow `enable()`. Or it may omit the dylib at packaging time. Decide per-module — translation might be Pro-only and worth omitting; monitor is Free and always shipped.

---

## 14. References

- Existing toggle layer: `crates/atlas-core/src/features.rs`
- Companion plugin design (third-party extension): `2026-05-24-plugin-system-design.md`
- Edition layer (commercial boundary): `2026-05-22-packaging-and-editions-v1.md`
- `libloading` crate: <https://docs.rs/libloading>
- Rust FFI safety patterns: <https://doc.rust-lang.org/nomicon/ffi.html>
- macOS dylib loading semantics: `dlopen(3)` man page
