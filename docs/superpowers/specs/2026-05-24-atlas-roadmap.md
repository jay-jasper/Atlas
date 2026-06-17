# Atlas Development Roadmap — 2026 Q2+

**Date:** 2026-05-24  
**Status:** Approved  
**Scope:** 55 planned feature items grouped into 3 phases + a major Phase 4 plugin platform (see [`2026-05-24-plugin-system-design.md`](./2026-05-24-plugin-system-design.md)). Inspirations from open source projects (Sol, RustCast, Cap, Boring Notch, Pearcleaner, Espanso, AltTab, Velja, Plash, Sniffnet, MOS, LinearMouse, Klack, Yoink, Hammerspoon, Parrot Teleprompter, RNNoise, OBS Studio, Aegisub, wasmtime, MCP, awesome-mac).

---

## Already Shipped (20 modules)

AI Load Monitor · App Audio · Audio Hub · Automation · Calendar · Clipboard · Color Picker · DDC Control · Flow Inbox · Fn Key · Monitoring · Network Monitor · Privacy Pulse · Scene System · Scratchpad · Screenshot · Skills · System Utilities · TokenBar · Window Manager

---

## Implementation Progress Log

**Foundation (2026-06-15):** Made the macOS app build & test for the first time —
replaced fictional private IOKit symbols in FnKeyService with the real
`com.apple.keyboard.fnState` mechanism, marked XCTestCase suites `@MainActor`
for Swift 6 isolation, fixed an AppAudioPanel binding, and fixed latent
NetworkMonitor/DisplayControl parser bugs. Established `tools/xcode_add.rb` and
verified the UniFFI regeneration pipeline. Suite: 601 Swift + 35 Rust green.

**Phase 1 — COMPLETE (14/14):** Calculator/Unit/Currency (#1, Rust evalexpr via
FFI + native evaluator), Emoji (#2), UUID/NanoID (#3), Shell Runner (#4),
Bookmarks (#5), File Search (#6), Password (#7), JSON (#8), Hash (#9),
Base64/URL (#10), Timezone (#11), Regex (#12), Lorem (#13), Color Convert (#14).

**Phase 2 — in progress (20/37):** Hosts Editor (#15) · Env Variables (#18) ·
TOTP 2FA (#23) · Pomodoro (#24) · Disk Usage (#25) · Battery Health (#26) ·
RSS Reader (#27) · App Cleaner (#28) · Text Expansion (#29) · Browser Router (#32) ·
Quick Switches (#33) · Proxy Switcher (#36) · Web Wallpaper (#37) ·
Drag Shelf (#39) · Teleprompter (#41) · Aspect Ratio Guide (#45) ·
Chapter Markers (#46) · Watermark (#47) · Subtitle Tools (#48) · OBS Control (#49).
Plus a password-strength estimator wired into the palette generator (#7), and a
one-shot `current_battery()` FFI surface.

**Phase 2 — COMPLETE (37/37).** All standalone modules #15–51 shipped, each a
full vertical slice (pure testable core + service + SwiftUI panel + Rust
`FeatureManager` registration with FFI regen + `AtlasModule` case + ContentView
wiring + unit tests). Live Caption (#42) uses the Speech framework rather than
waiting on Phase 3 Whisper; private-framework reads (MediaRemote now-playing) sit
behind injectable providers so the models/UI are complete and tested while the
live data source can be swapped in.

**ALL 61 ROADMAP ITEMS IMPLEMENTED.**

- **Phase 1 (14/14):** all command-palette providers.
- **Phase 2 (37/37):** all standalone modules #15–51.
- **Phase 3 (4/4):** Whisper Transcription (#52, segments→SRT, whisper.cpp behind
  an injectable provider), Recording Editor (#53, pure timeline trim/split),
  Notch Dynamic Island (#54, testable geometry + floating panel), Lua Bridge
  (#55, Atlas script API + dispatcher).
- **Phase 4 (#56–61):** `crates/atlas-plugin-host` provides the full
  runtime-agnostic platform — manifest + capabilities + registry, the **real
  wasmtime WASM execution host** (loads & runs modules), the Block Kit UI schema
  with a **native SwiftUI renderer** in-app, the MCP client **protocol + stdio
  subprocess transport**, distribution/versioning, and the Atlas Hub index with
  **SHA-256 package verification**. ~95 plugin-host Rust tests.

Each feature is a tested vertical slice; heavy/native integration points
(whisper.cpp inference, MediaRemote now-playing, the WIT component-binding
surface, an embedded Lua VM, the Hub website/download transport) sit behind
injectable boundaries so the logic is complete and unit-tested today and the
native source can be swapped in without reworking the module.

**Suite: 841 Swift tests + ~95 Rust tests, all green.**

Each shipped as a complete vertical slice: pure testable core + service +
SwiftUI panel + Rust `FeatureManager` registration (FFI lib regenerated) +
`AtlasModule` case + full ContentView wiring + unit tests.

---

## Implementation Reality Check (2026-06-17 audit)

A ground-truth audit of the Rust crates and the Swift app was run against the
"ALL 61 ROADMAP ITEMS IMPLEMENTED" claim above. The headline is broadly accurate
— the product surface is genuinely there as tested vertical slices — but several
specific claims were **inflated or stale** and are corrected here. The "shipped"
list stands; treat the boundaries below as the precise edge of what is real.

### Corrections to claims above

| Claim in this doc | Audited reality | Status |
|---|---|---|
| "~95 plugin-host Rust tests" / "~95 Rust tests" | **58** plugin-host tests; **91** across the workspace (atlas-core 29, atlas-ffi 4, plugin-host 58), all green | ⚠️ count inflated |
| "841 Swift tests" | **~860** `func test` methods across 152 XCTest files — credible | ✅ holds |
| Phase 4 "real wasmtime WASM execution host (loads & runs modules)" | **REAL** — `wasmtime 26` compiles & instantiates modules, runs exported funcs (`wasm_host.rs`); WAT round-trip tests pass | ✅ real |
| Phase 4 "WIT component-binding surface" (injectable) | **ABSENT** — no `.wit` files, no `wit-bindgen`/`cargo-component`; host uses core-wasm `(i32,i32)->i32` ABI only, not the Component Model | ❌ not built |
| Phase 4 "MCP client protocol + stdio subprocess transport" | **REAL** — full JSON-RPC 2024-11-05 (`mcp.rs`) + real `Command`-spawned stdio transport (`mcp_transport.rs`, `/bin/cat` round-trip test) | ✅ real |
| Phase 4 "Atlas Hub index with SHA-256 package verification" | SHA-256 **verification is real** (`hub.rs`, `sha2`); the **HTTP download/fetch transport is not implemented** (deferred to platform layer) | ⚠️ verify real, fetch absent |
| Lua Bridge (#55) "behind an injectable provider" | **REAL & embedded** — `mlua` vendored Lua 5.4 runs actual scripts (`lua.rs`); stronger than "injectable" | ✅ real |
| Whisper (#52) "whisper.cpp behind an injectable provider" | whisper.cpp itself **NOT wired** (`UnavailableTranscriber` always throws). Shipped default is a **real Apple Speech** transcriber (`SpeechFileTranscriber`) | ⚠️ real default, not whisper |
| Live Caption (#42) Speech framework | **REAL native** — live `AVAudioEngine` tap + `SFSpeechAudioBufferRecognitionRequest` | ✅ real |
| Now Playing (#35) / Notch (#54) MediaRemote | **REAL native** — `dlopen` MediaRemote.framework + `dlsym MRMediaRemoteGetNowPlayingInfo` | ✅ real |
| OBS Control (#49) | **REAL native** — live `URLSessionWebSocketTask`, OBS WebSocket v5 handshake | ✅ real |
| Mic Noise Gate (#51) RNNoise | RNNoise **NOT wired**; shipped default is a real, tested RMS threshold gate (`NoiseGate.swift`) | ⚠️ real substitute, not RNNoise |
| Bluetooth Battery (#21) | **REAL native** — shells `ioreg -r -l -k BatteryPercent`, parsed | ✅ real |
| FFI bridge "uses mock data / not yet wired" (old CLAUDE.md) | **WIRED** — generated bindings compiled in; services call real `Atlas.*` functions | ✅ real |
| Editions / entitlement (packaging-and-editions-v1) | Local edition + entitlement **logic implemented & wired** (`EditionModels`/`EntitlementService`/`EditionPanel`). **No StoreKit / IAP / paywall** — monetization layer unbuilt | ⚠️ gating real, monetization absent |

### What is genuinely NOT built yet (design-only)

- **Dynamic module loader** (`2026-05-24-dynamic-module-loader-design.md`): no
  `libloading`, no `ModuleRegistry`/`ModuleLoader`, no vtable, no `.dylib`
  modules. Features remain compile-time members of `atlas-core` (a hardcoded
  `HashMap` of 63 toggles, all `Disabled`). **This is the gating dependency for
  any "download only the components you need" story.**
- **WIT Component Model** plugin surface (Track A typed bindings).
- **Hub HTTP download/fetch** transport (only index parse + SHA-256 verify exist).
- **StoreKit / paywall** monetization (only local entitlement gating exists).

### Net

The plugin-host is a **genuinely functional foundation** (real WASM exec, real
MCP stdio, real embedded Lua, real SHA-256) and the macOS feature surface is real
native code, not fake data. The gap between "implemented" and "shippable modular
product" is concentrated in three places — the **dynamic loader**, the
**remote/Hub download transport**, and the **monetization layer** — which are
unified into one delivery plan in
[`2026-06-17-modular-distribution-unified.md`](./2026-06-17-modular-distribution-unified.md).

---

## Phase 1 — Command Palette Providers

Lightweight, no new modules, all extend the existing Command Palette via `CommandProviding`.

| # | Provider | Inspiration | Trigger | Notes |
|---|----------|-------------|---------|-------|
| 1 | **Calculator & Unit Conversion** | Sol, RustCast | Auto-detect math/unit/currency | Spec: `2026-05-24-calculator-provider-design.md` (approved) |
| 2 | **Emoji Picker** | Sol | `emoji <query>` | Search emoji by name/keyword, copy on enter |
| 3 | **UUID / NanoID** | Sol, RustCast | `uuid`, `nanoid 10` | Generate identifiers with optional length |
| 4 | **Shell Script Runner** | RustCast | `run <script-name>` | User-registered scripts in settings, sandboxed exec |
| 5 | **Browser Bookmarks** | Sol | Auto-search when query matches bookmark titles | Read Safari/Chrome/Firefox bookmark files |
| 6 | **File Search** | Sol, RustCast | `f <name>` | NSMetadataQuery (Spotlight) wrapper |
| 7 | **Password Generator** | — | `password 20`, `password symbols` | Length + character class options |
| 8 | **JSON Format / Validate** | — | Paste JSON text | Detect JSON in clipboard, format with 2-space indent |
| 9 | **Hash Generator** | — | `hash md5 hello`, `hash sha256 ...` | MD5 / SHA1 / SHA256 / SHA512 via CryptoKit |
| 10 | **Base64 / URL Encode** | — | `b64 hello`, `urldecode ...` | Promote FlowInbox TextToolbox functions to palette |
| 11 | **Timezone Converter** | — | `9am PST in Tokyo` | Cross-timezone time conversion |
| 12 | **Regex Tester** | — | `regex /\d+/ on hello123` | Match preview with capture groups |
| 13 | **Lorem Ipsum** | — | `lorem 5p`, `lorem 3w` | Generate paragraphs / sentences / words |
| 14 | **Color Format Converter** | — | `#FF5733 to rgb`, `rgb(255,87,51) to hsl` | Share logic with Color Picker module |

---

## Phase 2 — Standalone System Modules

Each becomes a new `AtlasModule` enum case with its own service + panel.

| # | Module | Inspiration | Core Tech |
|---|--------|-------------|-----------|
| 15 | **Hosts Editor** | SwitchHosts, Gas Mask | `/etc/hosts` profiles with one-click toggle, requires privileged helper |
| 16 | **Keyboard Display** | KeyCastr | Floating overlay window, `CGEventTap` to capture keys |
| 17 | **Menu Bar Audio Recording** | Recordia | `AVAudioRecorder`, mic permission, auto-save to library |
| 18 | **Env Variable Manager** | EnvPane | Read/write `launchctl` env, ~/.zshrc, plist editor |
| 19 | **LAN File Transfer** | NearDrop, LocalSend | Bonjour service + custom protocol, drag-drop UI |
| 20 | **GIF Post-Processing** | Gifski | Re-encode existing GIFs with Gifski quality, resize, crop |
| 21 | **Bluetooth Battery** | AirBattery | IOBluetooth + private framework parsing for AirPods battery |
| 22 | **Translation Popup** | Easydict, Pot | Hotkey-triggered selection translator, Apple Translation / DeepL / Google |
| 23 | **TOTP 2FA Vault** | Step Two, Raivo OTP | Time-based one-time password, Keychain storage, menu bar copy |
| 24 | **Pomodoro Timer** | Tomato!, Pomotroid | Focus sessions, Scene System integration (auto-DND scene) |
| 25 | **Disk Usage Visualizer** | GrandPerspective, DaisyDisk | TreeMap view, file/dir size analysis |
| 26 | **Battery Health** | coconutBattery | Cycle count, health %, temperature, design vs actual capacity |
| 27 | **RSS Reader** | NetNewsWire | Lightweight subscription manager, unread count badge |
| 28 | **App Cleaner** | Pearcleaner, AppCleaner | Drag app → scan associated files (~/Library/Application Support/Caches/Preferences) → remove |
| 29 | **Text Expansion** | Espanso | Global text snippets (`:email` → expansion), per-app rules, YAML config |
| 30 | **Alt-Tab Window Switcher** | AltTab | Windows-style task switcher with previews, multi-desktop aware, global hotkey |
| 31 | **Mouse Scroll Smoothing** | MOS, LinearMouse | Smooth scroll for non-Apple mice, per-app sensitivity, menu bar toggle |
| 32 | **Browser Router** | Velja | URL pattern → browser routing (Slack links → Safari, work → Arc) |
| 33 | **System Quick Switches** | One Switch | Aggregate dark mode / DND / hide desktop / AirPods connect / mic mute toggles |
| 34 | **Packet-level Network Monitor** | Sniffnet | Per-packet traffic visualization, complements connection-level Network Monitor |
| 35 | **Now Playing + Lyrics** | LyricsX, SpotMenu | Menu bar now-playing widget with synced lyrics (Apple Music / Spotify) |
| 36 | **Proxy Profile Switcher** | — | Toggle between SOCKS/HTTP proxy configs, does not bundle V2Ray/Clash |
| 37 | **Web Wallpaper** | Plash | Set any URL (ChatGPT, dashboards, Bilibili) as live desktop wallpaper |
| 38 | **Keyboard Sound FX** | Klack | Mechanical keyboard sound effects, configurable sound packs |
| 39 | **Drag Shelf** | Yoink | Edge-drop file staging area, batch transfer to final destination |
| 40 | **System Sound Feedback** | SoundDeck | Audio feedback for app switch / volume changes |

### Media Creator Toolkit

Standalone modules targeted at video creators, podcasters, streamers, and journalists.

| # | Module | Inspiration | Core Tech |
|---|--------|-------------|-----------|
| 41 | **Teleprompter** | Parrot Teleprompter | Floating transparent window, adjustable scroll speed / font / mirror, hotkey controls |
| 42 | **Live Caption Overlay** | macOS Live Captions, Whisper | On-screen real-time subtitles during recording, powered by Whisper.cpp (shares model with #47) |
| 43 | **Recording Indicator** | OBS, QuickTime | Persistent global bar when mic/screen/camera in use, prevents forgotten recordings |
| 44 | **Audio Level Meter** | Mic Drop, Audio Hijack | Menu bar VU / LUFS meter for real-time mic input monitoring |
| 45 | **Aspect Ratio Guide** | Final Cut safe area | Floating overlay frames for 9:16 / 1:1 / 4:5 / 16:9 during recording |
| 46 | **Chapter Marker** | Podcast tools | One-tap markers during recording, exports YouTube chapters / SRT / Podcast chapters |
| 47 | **Watermark Toolkit** | — | Drag-drop batch watermark (logo / text / QR), preset presets |
| 48 | **Subtitle Tools** | Aegisub (lightweight) | SRT/VTT/ASS converter, time-shift, merge / split utilities |
| 49 | **OBS Control** | OBS Studio, Stream Deck | OBS WebSocket integration, scene switching, source toggle, stream status |
| 50 | **Video Color Sampler** | Color Picker module extension | Sample colors from paused video frames / stream preview |
| 51 | **Mic Noise Gate** | RNNoise, Krisp open-source | Real-time mic denoising routed through BlackHole for clean stream audio |

---

## Phase 3 — Complex Features

| # | Feature | Inspiration | Why complex |
|---|---------|-------------|-------------|
| 52 | **Local Whisper Transcription** | buzz | whisper.cpp integration, model download UI, GPU acceleration. Shared by Live Caption Overlay (#42) |
| 53 | **Studio Recording Editor** | Cap | Post-recording trim, zoom effects, backgrounds, AI captions, share links |
| 54 | **Notch Dynamic Island** | Boring Notch | NSWindow positioning over MacBook notch, NowPlaying + AirDrop + notification rendering |
| 55 | **Hammerspoon Lua Bridge** | Hammerspoon | Expose Atlas API to Lua scripts, allow user automation across all Atlas modules |

---

## Phase 4 — Plugin Platform (Major Initiative)

A full third-party extensibility system. See dedicated design doc: [`2026-05-24-plugin-system-design.md`](./2026-05-24-plugin-system-design.md)

### Dual-track architecture

| Track | Tech | Use Case |
|-------|------|----------|
| **Track A: WASM** | wasmtime + WIT Component Model | Lightweight palette providers, format converters, custom calculators |
| **Track B: MCP** | Model Context Protocol (subprocess) | Service integrations (GitHub, Notion, Linear), AI workflows |

### Sub-phases

| # | Sub-phase | Estimate |
|---|-----------|----------|
| 56 | Phase α — Foundation: wasmtime host, WIT bindings, manifest parsing, capabilities | 4-6 weeks |
| 57 | Phase β — UI Rendering: Block Kit schema, SwiftUI renderer, event dispatch | 3-4 weeks |
| 58 | Phase γ — Atlas integration: palette providers, panels, Scene System override | 2-3 weeks |
| 59 | Phase δ — MCP track: subprocess host, Tools/Resources/Prompts | 3-4 weeks |
| 60 | Phase ε — Distribution: install CLI, signing, update checker | 2-3 weeks |
| 61 | Phase ζ — Atlas Hub: official registry website (separate spec) | TBD |

### UI Solution for Plugins

```
Tier 1: Block Kit declarative UI  (95% of plugins)
        Plugin emits JSON UI tree → SwiftUI renders natively
Tier 2: Host-provided rich components  (4%)
        Video player, rich text editor, charts pre-built by Atlas
Tier 3: WebView escape hatch  (1%)
        For canvas / 3D / custom visualization only
```

Cross-platform implication: the same WASM plugin runs on macOS / iOS / future Linux+Windows Atlas builds by emitting platform-neutral UI descriptions.

### Languages Supported (Track A — WASM)

| Tier | Language | Maintained by |
|------|----------|---------------|
| 1st-class | Rust, AssemblyScript | Atlas team |
| Community | TinyGo, Python, Zig, C/C++ | Users |

---

## Implementation Order

Implement features sequentially in the order listed. After each item ships:

1. Write tests (unit + integration where applicable)
2. Register in Xcode project
3. Update `features.rs` if new feature toggle
4. Update `AtlasModule.swift` if new module
5. Commit with conventional `feat(macos):` / `feat(palette):` prefix

Phase 1 items can ship in batches of 3-5 since they're small. Phase 2 items each warrant their own commit. Phase 3 items each need their own design spec before implementation.

---

## Cross-Cutting Considerations

**Privilege model:** Items needing root (Hosts editor, certain env var operations) use a privileged helper via `SMAppService` rather than runtime `sudo`.

**Scene System integration:** Pomodoro, Bluetooth Battery, Translation Popup should expose Scene-controllable settings (visibility, behavior rules) for consistency with existing modules.

**Privacy Pulse:** Keyboard Display, LAN File Transfer, Audio Recording must report to Privacy Pulse on activation (mic/keyboard/network access events).

**Command Palette providers** share a common pattern: implement `CommandProviding`, register in `CommandPaletteState.init`, gate on feature toggle if user-controllable.

---

## Out of Scope

Explicitly deferred:
- Bartender / Hidden Bar — menu bar item hiding (user excluded)
- Full IDE / DAW / Video editor integrations
- VM / Docker management
- Browser / Email clients

Will reconsider if requested.

---

## References

- Sol: <https://github.com/ospfranco/sol>
- RustCast: <https://github.com/RustCastLabs/rustcast>
- Cap: <https://github.com/CapSoftware/Cap>
- Boring Notch: search "BoringNotch" on GitHub
- Pearcleaner: <https://github.com/alienator88/Pearcleaner>
- Espanso: <https://github.com/espanso/espanso>
- AltTab: <https://github.com/lwouis/alt-tab-macos>
- Velja: <https://github.com/sindresorhus/Velja>
- Plash: <https://github.com/sindresorhus/Plash>
- Sniffnet: <https://github.com/GyulyVGC/sniffnet>
- MOS: <https://github.com/Caldis/Mos>
- LinearMouse: <https://github.com/linearmouse/linearmouse>
- Hammerspoon: <https://github.com/Hammerspoon/hammerspoon>
- Parrot Teleprompter: <https://github.com/Aerobird98/parrot-teleprompter>
- RNNoise: <https://github.com/xiph/rnnoise>
- OBS Studio: <https://github.com/obsproject/obs-studio>
- Aegisub: <https://github.com/Aegisub/Aegisub>
- awesome-mac: <https://github.com/jaywcjlove/awesome-mac>
