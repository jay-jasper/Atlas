# Building Atlas

The Rust UDL is the public API source of truth. After changing the UDL or Rust FFI implementation, run `./scripts/generate_uniffi_swift.sh`. Commit the generated Swift, C header, module maps, and both universal static libraries: `libatlas_ffi.a` for Direct and `libatlas_ffi_store.a` for Store. The static libraries are Git LFS objects; CI regenerates them before every macOS build so releases do not depend on a stale artifact.

Use the `Atlas Store` scheme for Mac App Store builds and `Atlas Direct` for Developer ID builds. Run `ruby platforms/macos/tools/configure_distributions.rb` if build configurations need to be recreated.

All commits must pass Rust format, strict Clippy, workspace tests, and both macOS scheme test suites. `Cargo.lock` is committed so CI and releases resolve identical dependencies.

Run `scripts/audit_dependencies.sh` for RustSec scanning. Its two explicit exceptions are Linux-only XCap build dependencies that are not compiled into either macOS architecture; the macOS dependency graph currently completes with no advisories or maintenance warnings.
