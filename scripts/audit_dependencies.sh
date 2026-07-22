#!/usr/bin/env bash
set -euo pipefail

# These two advisories are reachable only through XCap's Linux/X11/Wayland
# target dependencies (xcb/wayland-scanner). Atlas ships macOS binaries and
# does not compile or execute those crates. Keep the exceptions narrow and
# remove them when XCap updates its Linux dependency graph.
cargo audit \
  --target-os macos \
  --target-arch aarch64 \
  --target-arch x86_64 \
  --ignore RUSTSEC-2026-0194 \
  --ignore RUSTSEC-2026-0195
