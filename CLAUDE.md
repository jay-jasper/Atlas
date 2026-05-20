# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Atlas** is an AI-native macOS menu bar application designed to replace 10+ standalone utilities (system monitoring, screen capture, port management, window management, etc.) with a single lightweight, modular app. The architecture is a **Rust core + SwiftUI frontend** connected via a UniFFI FFI bridge.

## Commands

### Rust

```bash
# Build all crates
cargo build

# Run all tests
cargo test

# Run tests for a specific crate
cargo test -p atlas-core
cargo test -p atlas-ffi

# Run a single test by name
cargo test -p atlas-core test_feature_toggle
```

### macOS App

Open `platforms/macos/` in Xcode to build and run the Swift app. There is no Makefile or script for this — Xcode is required.

## Architecture

### Two-layer design

```
platforms/macos/   ← SwiftUI app (menu bar UI)
      ↕  UniFFI FFI
crates/atlas-ffi/  ← FFI bridge (exposes Rust to Swift)
      ↕  Rust library
crates/atlas-core/ ← Core logic (capture, monitoring, features)
```

### `crates/atlas-core`

Pure Rust logic with no FFI concerns:

- `features.rs` — `FeatureManager`: a `HashMap`-backed toggle system for named modules (`monitoring`, `screenshot`, `window-manager`). All features start `Disabled`.
- `capture/engine.rs` — `CaptureEngine`: screen capture using the `screenshots` crate. Returns raw PNG bytes. Currently supports primary monitor only.
- `monitor/collector.rs` — `Collector`: polls CPU, memory, and network delta bytes per second using `sysinfo`. Requires two successive calls to compute meaningful CPU and network rates.
- `monitor/port_master.rs` — Port-to-process lookup via `lsof -sTCP:LISTEN`, process kill via `kill -9`. macOS-only.
- `monitor/models.rs` — shared data structs (`SystemSnapshot`, `PortProcessInfo`).

### `crates/atlas-ffi`

UniFFI bridge that exposes `atlas-core` to Swift:

- `atlas.udl` — the UniFFI Interface Definition Language file. **This is the source of truth for the public API surface.** Any new function exposed to Swift must be declared here first.
- `build.rs` — calls `uniffi::generate_scaffolding("src/atlas.udl")` at compile time to auto-generate Rust scaffolding.
- `lib.rs` — implements the UDL-declared functions using three global statics:
  - `CORE: Lazy<Mutex<AtlasCore>>` — shared singleton
  - `MONITOR_HANDLE: Lazy<Mutex<Option<JoinHandle<()>>>>` — controls the background monitoring task
  - `RUNTIME: Lazy<Runtime>` — single shared Tokio runtime for all async work

### `platforms/macos/Atlas`

SwiftUI app structured as a `MenuBarExtra` with `.window` style:

- `AtlasApp.swift` — app entry point; registers the menu bar item.
- `ContentView.swift` — main panel with sections for screenshot capture, system monitoring, port master, and feature toggles. **The `AtlasBridge` class currently uses mock data** (random values, print statements) and is not yet wired to the real UniFFI-generated bindings.
- `SelectionOverlay.swift` — full-screen drag gesture overlay for region capture; calls back with a `CGRect` on release.

### FFI integration status

The Rust side is fully implemented and tested. The Swift side uses a placeholder `AtlasBridge` class. The next integration step is to import the UniFFI-generated Swift module (`AtlasFFI`) into the Xcode project and replace `AtlasBridge` with the real generated bindings.

## Key conventions

- New feature modules must be registered in `FeatureManager::new()` in `features.rs` and declared in `atlas.udl` before being callable from Swift.
- The monitoring callback (`SystemMonitorCallback`) runs on a Tokio background thread — UI updates from Swift must be dispatched to `DispatchQueue.main`.
- `port_master.rs` shells out to `lsof` and `kill`; tests that exercise these spawn real processes and are not mocked.
