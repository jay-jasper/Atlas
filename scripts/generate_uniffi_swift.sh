#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/platforms/macos/Generated/AtlasFFI"
LIB_DYLIB="$ROOT_DIR/target/release/libatlas_ffi.dylib"

if command -v rustup >/dev/null 2>&1; then
  CARGO_CMD=(rustup run stable cargo)
  export RUSTC="$(rustup which rustc)"
  export RUSTDOC="$(rustup which rustdoc)"
else
  CARGO_CMD=(cargo)
  export RUSTC="${RUSTC:-$(command -v rustc)}"
  export RUSTDOC="${RUSTDOC:-$(command -v rustdoc)}"
fi

RUST_SYSROOT="$("$RUSTC" --print sysroot)"

REMAP_RUSTFLAGS=(
  "--remap-path-prefix=$ROOT_DIR=."
  "--remap-path-prefix=$HOME/.cargo=.cargo"
  "--remap-path-prefix=$HOME/.rustup=.rustup"
  "--remap-path-prefix=$RUST_SYSROOT=.rustup/toolchain"
  "--remap-path-prefix=$HOME=.home"
)
export RUSTFLAGS="${RUSTFLAGS:-} ${REMAP_RUSTFLAGS[*]}"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
export CFLAGS="${CFLAGS:-} -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
export CFLAGS_aarch64_apple_darwin="$CFLAGS"
export CFLAGS_x86_64_apple_darwin="$CFLAGS"
export ATLAS_RUST_ENV_CONFIGURED=1

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

"${CARGO_CMD[@]}" build -p atlas-ffi --release
"${CARGO_CMD[@]}" run -p uniffi-swift-bindgen -- "$LIB_DYLIB" "$OUT_DIR"
perl -pi -e 's/[ \t]+$//' "$OUT_DIR/atlas.swift" "$OUT_DIR/atlasFFI.h"

"$ROOT_DIR/scripts/build_uniffi_static.sh" \
  direct "$OUT_DIR/libatlas_ffi.a" arm64 x86_64
"$ROOT_DIR/scripts/build_uniffi_static.sh" \
  store "$OUT_DIR/libatlas_ffi_store.a" arm64 x86_64

cp "$OUT_DIR/atlas_ffi.modulemap" "$OUT_DIR/module.modulemap"

test -f "$OUT_DIR/atlas.swift"
test -f "$OUT_DIR/atlasFFI.h"
test -f "$OUT_DIR/atlas_ffi.modulemap"
test -f "$OUT_DIR/module.modulemap"
test -f "$OUT_DIR/libatlas_ffi.a"
test -f "$OUT_DIR/libatlas_ffi_store.a"

echo "Generated UniFFI Swift artifacts in $OUT_DIR"
