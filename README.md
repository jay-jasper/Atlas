# Atlas

Atlas is an AI-native macOS utility suite implemented as a SwiftUI menu bar app with a Rust core exposed through UniFFI.

## Build and test

Requirements: Xcode 16+, the stable Rust toolchain, and both `aarch64-apple-darwin` and `x86_64-apple-darwin` Rust targets.

```bash
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
./scripts/generate_uniffi_swift.sh
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Store" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

`Atlas Store` is sandboxed and links a dedicated FFI library that excludes Wasmtime, QuickJS, dynamic module loading, the private MediaRemote provider, and the external updater. `Atlas Direct` supports signed licenses, executable plugins, privileged utilities, and the signed external updater.

## Security and privacy

- WASM plugins have fuel, memory, and wall-clock limits; MCP subprocesses have message, stderr, and response time limits.
- JS plugins run in isolated QuickJS heaps on dedicated threads with 32 MB heap, 512 KB stack, and a 200 ms watchdog.
- The legacy embedded Lua bridge is isolated behind the Rust `lua` feature and is excluded from production FFI builds unless explicitly requested.
- Hub-downloaded plugin packages and update manifests are verified with Ed25519 and SHA-256.
- Local plugin installs require explicit capability approval; a changed manifest invalidates the saved approval.
- Executable plugins run in authenticated per-plugin Runner processes and render only validated declarative UI; packages are immutable, content-addressed, and reverified on every activation.
- Capability grants are target-scoped and may be revoked independently. External files use opaque security-scoped bookmark handles rather than paths.
- The App Store build contains neither the Runner helper nor executable plugin runtime dependencies.
- Scratchpad and clipboard history payloads are encrypted with AES-GCM; the content key is stored in macOS Keychain.
- Clipboard history excludes common secrets, OTPs, and Luhn-valid payment-card numbers and expires after seven days by default.

See [docs/BUILDING.md](docs/BUILDING.md), [docs/PRIVACY.md](docs/PRIVACY.md), and [docs/RELEASING.md](docs/RELEASING.md).

Plugin release gates include hostile-package tests and a deterministic soak:

```bash
cargo test -p atlas-plugin-host --test malicious_plugins
ATLAS_PLUGIN_SOAK_SECONDS=300 ./scripts/test_plugin_soak.sh
```

Atlas Direct includes a compatibility toolchain for public Raycast extensions:
canonical `@atlas/api`, semantic `@raycast/api` adapters, static capability
analysis, deterministic packaging, non-destructive migration, and a pinned
30-extension release corpus. See
[plugin development](docs/PLUGIN_DEVELOPMENT.md) and
[Raycast compatibility](docs/RAYCAST_COMPATIBILITY.md).
