# Atlas Development Roadmap — 2026 Q2+

**Date:** 2026-05-24  
**Status:** Approved  
**Scope:** 55 planned feature items grouped into 3 phases + a major Phase 4 plugin platform (see [`2026-05-24-plugin-system-design.md`](./2026-05-24-plugin-system-design.md)). Inspirations from open source projects (Sol, RustCast, Cap, Boring Notch, Pearcleaner, Espanso, AltTab, Velja, Plash, Sniffnet, MOS, LinearMouse, Klack, Yoink, Hammerspoon, Parrot Teleprompter, RNNoise, OBS Studio, Aegisub, wasmtime, MCP, awesome-mac).

---

## Already Shipped (20 modules)

AI Load Monitor · App Audio · Audio Hub · Automation · Calendar · Clipboard · Color Picker · DDC Control · Flow Inbox · Fn Key · Monitoring · Network Monitor · Privacy Pulse · Scene System · Scratchpad · Screenshot · Skills · System Utilities · TokenBar · Window Manager

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
