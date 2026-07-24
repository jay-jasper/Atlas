# Building Atlas

The Rust UDL is the public API source of truth. After changing the UDL or Rust FFI implementation, run `./scripts/generate_uniffi_swift.sh`. Commit the generated Swift, C header, module maps, and both universal static libraries: `libatlas_ffi.a` for Direct and `libatlas_ffi_store.a` for Store. The static libraries are Git LFS objects; CI regenerates them before every macOS build so releases do not depend on a stale artifact.

Use the `Atlas Store` scheme for Mac App Store builds and `Atlas Direct` for Developer ID builds. Run `ruby platforms/macos/tools/configure_distributions.rb` if build configurations need to be recreated.

Direct builds compile `atlas-plugin-runner` for every active architecture, embed it at `Atlas.app/Contents/Helpers`, and sign it with the deny-by-default Runner entitlements. Store builds remove that helper and link `atlas_ffi_store`, whose dependency graph must not include the plugin host, package, JS, or Runner crates. `scripts/build_release.sh` verifies these invariants.

All commits must pass Rust format, strict Clippy, workspace tests, and both macOS scheme test suites. `Cargo.lock` is committed so CI and releases resolve identical dependencies.

Run `scripts/audit_dependencies.sh` for RustSec scanning. Its two explicit exceptions are Linux-only XCap build dependencies that are not compiled into either macOS architecture; the macOS dependency graph currently completes with no advisories or maintenance warnings.

Install `cargo-fuzz` with nightly Rust to build the package, protocol, and UI patch fuzz targets under each crate's `fuzz/` directory. Run `ATLAS_PLUGIN_SOAK_SECONDS=300 ./scripts/test_plugin_soak.sh` before a release; scheduled CI uses a dedicated macOS runner for the 24-hour gate.

Install the locked JavaScript workspace before Rust plugin-builder tests:

```bash
pnpm install --frozen-lockfile
pnpm test && pnpm typecheck && pnpm build
cargo test -p atlas-plugin-builder -p atlas-plugin-runner
./scripts/test_raycast_compat.sh
```

The compatibility gate performs a sparse checkout of the immutable official
MIT corpus under ignored `.cache/raycast-corpus`; no upstream source is
committed.
