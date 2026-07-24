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

if cargo tree -p atlas-ffi --no-default-features | grep -Eq 'atlas-plugin-(host|runner|js|package)'; then
  echo "Store FFI dependency graph includes executable plugin crates" >&2
  exit 1
fi

RUNNER_ENTITLEMENTS="platforms/macos/Atlas/Plugins/AtlasPluginRunner.entitlements"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$RUNNER_ENTITLEMENTS")" = true
for entitlement in \
  com.apple.security.network.client \
  com.apple.security.network.server \
  com.apple.security.files.user-selected.read-only \
  com.apple.security.files.user-selected.read-write \
  com.apple.security.automation.apple-events \
  com.apple.security.inherit
do
  test "$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$RUNNER_ENTITLEMENTS")" = false
done
