#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/platforms/macos/Generated/AtlasFFI"
LIB_DYLIB="$ROOT_DIR/target/release/libatlas_ffi.dylib"
MACOS_TARGETS=("aarch64-apple-darwin" "x86_64-apple-darwin")

if command -v rustup >/dev/null 2>&1; then
  CARGO_CMD=(rustup run stable cargo)
  export RUSTC="$(rustup which rustc)"
  export RUSTDOC="$(rustup which rustdoc)"
else
  CARGO_CMD=(cargo)
fi

REMAP_RUSTFLAGS=(
  "--remap-path-prefix=$ROOT_DIR=."
  "--remap-path-prefix=$HOME/.cargo=.cargo"
)
export RUSTFLAGS="${RUSTFLAGS:-} ${REMAP_RUSTFLAGS[*]}"

ensure_rust_target() {
  local target="$1"

  if ! command -v rustup >/dev/null 2>&1; then
    return 0
  fi

  if ! rustup target list --installed | grep -qx "$target"; then
    rustup target add "$target"
  fi
}

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

"${CARGO_CMD[@]}" build -p atlas-ffi --release
"${CARGO_CMD[@]}" run -p uniffi-swift-bindgen -- "$LIB_DYLIB" "$OUT_DIR"

static_libs=()
for target in "${MACOS_TARGETS[@]}"; do
  ensure_rust_target "$target"
  "${CARGO_CMD[@]}" build -p atlas-ffi --release --target "$target"

  target_lib="$ROOT_DIR/target/$target/release/libatlas_ffi.a"
  stripped_lib="$OUT_DIR/libatlas_ffi-$target.a"
  cp "$target_lib" "$stripped_lib"
  strip -S -x "$stripped_lib"
  static_libs+=("$stripped_lib")
done

lipo -create "${static_libs[@]}" -output "$OUT_DIR/libatlas_ffi.a"
rm "${static_libs[@]}"

cp "$OUT_DIR/atlas_ffi.modulemap" "$OUT_DIR/module.modulemap"

test -f "$OUT_DIR/atlas.swift"
test -f "$OUT_DIR/atlasFFI.h"
test -f "$OUT_DIR/atlas_ffi.modulemap"
test -f "$OUT_DIR/module.modulemap"
test -f "$OUT_DIR/libatlas_ffi.a"

echo "Generated UniFFI Swift artifacts in $OUT_DIR"
