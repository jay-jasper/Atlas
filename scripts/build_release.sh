#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANNEL="${1:-direct}"
case "$CHANNEL" in
  direct)
    SCHEME="Atlas Direct"
    EXPORT_OPTIONS="$ROOT_DIR/scripts/ExportOptions-Direct.plist"
    ;;
  store)
    SCHEME="Atlas Store"
    EXPORT_OPTIONS="$ROOT_DIR/scripts/ExportOptions-Store.plist"
    ;;
  *)
    echo "usage: $0 [direct|store]" >&2
    exit 2
    ;;
esac

ARCHIVE="$ROOT_DIR/build/Atlas-$CHANNEL.xcarchive"
EXPORT_PATH="$ROOT_DIR/build/export-$CHANNEL"
"$ROOT_DIR/scripts/generate_uniffi_swift.sh"
ruby "$ROOT_DIR/platforms/macos/tools/configure_distributions.rb"
mkdir -p "$ROOT_DIR/build"
rm -rf "$ARCHIVE" "$EXPORT_PATH"
xcodebuild archive \
  -project "$ROOT_DIR/platforms/macos/Atlas.xcodeproj" \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS"

APP_PATH="$ARCHIVE/Products/Applications/Atlas.app"
RUNNER_PATH="$APP_PATH/Contents/Helpers/atlas-plugin-runner"
if [[ "$CHANNEL" == "direct" ]]; then
  test -x "$RUNNER_PATH"
  /usr/bin/codesign --verify --strict "$RUNNER_PATH"
  /usr/bin/codesign -d --entitlements :- "$RUNNER_PATH" 2>&1 \
    | /usr/bin/plutil -extract com.apple.security.app-sandbox raw - \
    | grep -qx true
else
  test ! -e "$RUNNER_PATH"
  if /usr/bin/nm -gj "$APP_PATH/Contents/MacOS/Atlas" | grep -Eq 'wasmtime|quickjs|atlas_plugin_runner'; then
    echo "Store binary contains executable plugin runtime symbols" >&2
    exit 1
  fi
fi

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

echo "Created $ARCHIVE and exported release to $EXPORT_PATH"
