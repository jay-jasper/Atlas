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
perl -pi -e 's/[ \t]+$//' "$OUT_DIR/atlas.swift" "$OUT_DIR/atlasFFI.h"

direct_static_libs=()
store_static_libs=()
for target in "${MACOS_TARGETS[@]}"; do
  ensure_rust_target "$target"
  "${CARGO_CMD[@]}" build -p atlas-ffi --release --target "$target"

  target_lib="$ROOT_DIR/target/$target/release/libatlas_ffi.a"
  direct_lib="$OUT_DIR/libatlas_ffi-$target.a"
  cp "$target_lib" "$direct_lib"
  strip -S -x "$direct_lib"
  direct_static_libs+=("$direct_lib")

  "${CARGO_CMD[@]}" build -p atlas-ffi --release --target "$target" --no-default-features
  store_lib="$OUT_DIR/libatlas_ffi_store-$target.a"
  cp "$target_lib" "$store_lib"
  strip -S -x "$store_lib"
  store_static_libs+=("$store_lib")
done

lipo -create "${direct_static_libs[@]}" -output "$OUT_DIR/libatlas_ffi.a"
lipo -create "${store_static_libs[@]}" -output "$OUT_DIR/libatlas_ffi_store.a"
rm "${direct_static_libs[@]}" "${store_static_libs[@]}"

for static_lib in "$OUT_DIR/libatlas_ffi.a" "$OUT_DIR/libatlas_ffi_store.a"; do
  for local_path in "$ROOT_DIR" "$HOME/.cargo" "$HOME/.rustup"; do
    if strings "$static_lib" | grep -F "$local_path"; then
      echo "error: $static_lib contains local path: $local_path" >&2
      exit 1
    fi
  done
done

cp "$OUT_DIR/atlas_ffi.modulemap" "$OUT_DIR/module.modulemap"

test -f "$OUT_DIR/atlas.swift"
test -f "$OUT_DIR/atlasFFI.h"
test -f "$OUT_DIR/atlas_ffi.modulemap"
test -f "$OUT_DIR/module.modulemap"
test -f "$OUT_DIR/libatlas_ffi.a"
test -f "$OUT_DIR/libatlas_ffi_store.a"

echo "Generated UniFFI Swift artifacts in $OUT_DIR"
