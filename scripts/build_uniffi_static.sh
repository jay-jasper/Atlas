#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARIANT="${1:-}"
OUTPUT_PATH="${2:-}"
shift 2 || true

if [[ "$VARIANT" != "direct" && "$VARIANT" != "store" ]] || [[ -z "$OUTPUT_PATH" ]]; then
  echo "usage: $0 <direct|store> <output-path> [arm64|x86_64 ...]" >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  set -- arm64 x86_64
fi

export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
if command -v rustup >/dev/null 2>&1; then
  CARGO_CMD=(rustup run stable cargo)
  export RUSTC="$(rustup which rustc)"
  export RUSTDOC="$(rustup which rustdoc)"
else
  CARGO_CMD=(cargo)
  export RUSTC="${RUSTC:-$(command -v rustc)}"
  export RUSTDOC="${RUSTDOC:-$(command -v rustdoc)}"
fi

if [[ "${ATLAS_RUST_ENV_CONFIGURED:-0}" != "1" ]]; then
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
fi

ensure_rust_target() {
  local target="$1"

  if command -v rustup >/dev/null 2>&1 \
    && ! rustup target list --installed | grep -qx "$target"; then
    rustup target add "$target"
  fi
}

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/atlas-uniffi-static.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

STATIC_LIBS=()
for architecture in "$@"; do
  case "$architecture" in
    arm64|aarch64-apple-darwin)
      rust_target="aarch64-apple-darwin"
      ;;
    x86_64|x86_64-apple-darwin)
      rust_target="x86_64-apple-darwin"
      ;;
    *)
      echo "unsupported Rust FFI architecture: $architecture" >&2
      exit 1
      ;;
  esac

  ensure_rust_target "$rust_target"
  cargo_arguments=(
    build
    --manifest-path "$ROOT_DIR/Cargo.toml"
    --package atlas-ffi
    --release
    --target "$rust_target"
  )
  if [[ "$VARIANT" == "store" ]]; then
    cargo_arguments+=(--no-default-features)
  fi
  "${CARGO_CMD[@]}" "${cargo_arguments[@]}"

  source_library="$ROOT_DIR/target/$rust_target/release/libatlas_ffi.a"
  staged_library="$STAGING_DIR/libatlas_ffi-$rust_target.a"
  cp "$source_library" "$staged_library"
  strip_log="$STAGING_DIR/strip-$rust_target.log"
  if ! strip -S -x "$staged_library" 2>"$strip_log"; then
    cat "$strip_log" >&2
    exit 1
  fi
  STATIC_LIBS+=("$staged_library")
done

mkdir -p "$(dirname "$OUTPUT_PATH")"
if [[ ${#STATIC_LIBS[@]} -eq 1 ]]; then
  cp "${STATIC_LIBS[0]}" "$OUTPUT_PATH"
else
  lipo -create "${STATIC_LIBS[@]}" -output "$OUTPUT_PATH"
fi

for local_path in "$ROOT_DIR" "$HOME/.cargo" "$HOME/.rustup"; do
  if LC_ALL=C grep -aFq "$local_path" "$OUTPUT_PATH"; then
    echo "error: $OUTPUT_PATH contains local path: $local_path" >&2
    exit 1
  fi
done

echo "Built $VARIANT Rust FFI library at $OUTPUT_PATH"
