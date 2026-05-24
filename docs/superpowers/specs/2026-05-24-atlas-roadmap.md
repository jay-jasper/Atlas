# Atlas Development Roadmap — 2026 Q2+

**Date:** 2026-05-24  
**Status:** Approved  
**Scope:** 44 planned feature items grouped into 3 phases, plus inspirations from open source projects (Sol, RustCast, Cap, Boring Notch, Pearcleaner, Espanso, AltTab, Velja, Plash, Sniffnet, MOS, LinearMouse, Klack, Yoink, Hammerspoon, awesome-mac).

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

---

## Phase 3 — Complex Features

| # | Feature | Inspiration | Why complex |
|---|---------|-------------|-------------|
| 41 | **Local Whisper Transcription** | buzz | whisper.cpp integration, model download UI, GPU acceleration |
| 42 | **Studio Recording Editor** | Cap | Post-recording trim, zoom effects, backgrounds, AI captions, share links |
| 43 | **Notch Dynamic Island** | Boring Notch | NSWindow positioning over MacBook notch, NowPlaying + AirDrop + notification rendering |
| 44 | **Hammerspoon Lua Bridge** | Hammerspoon | Expose Atlas API to Lua scripts, allow user automation across all Atlas modules |

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
- awesome-mac: <https://github.com/jaywcjlove/awesome-mac>
