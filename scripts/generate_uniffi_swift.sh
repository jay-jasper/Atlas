#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/platforms/macos/Generated/AtlasFFI"
LIB_DYLIB="$ROOT_DIR/target/release/libatlas_ffi.dylib"
LIB_STATIC="$ROOT_DIR/target/release/libatlas_ffi.a"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cargo build -p atlas-ffi --release
cargo run -p uniffi-swift-bindgen -- "$LIB_DYLIB" "$OUT_DIR"

cp "$LIB_STATIC" "$OUT_DIR/libatlas_ffi.a"

test -f "$OUT_DIR/atlas.swift"
test -f "$OUT_DIR/atlasFFI.h"
test -f "$OUT_DIR/atlas_ffi.modulemap"
test -f "$OUT_DIR/libatlas_ffi.a"

echo "Generated UniFFI Swift artifacts in $OUT_DIR"
