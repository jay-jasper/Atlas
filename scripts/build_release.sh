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
mkdir -p "$ROOT_DIR/build"
rm -rf "$ARCHIVE" "$EXPORT_PATH"
xcodebuild archive \
  -project "$ROOT_DIR/platforms/macos/Atlas.xcodeproj" \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

echo "Created $ARCHIVE and exported release to $EXPORT_PATH"
