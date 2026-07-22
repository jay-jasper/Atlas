#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <Atlas.app> <notary-keychain-profile>" >&2
  exit 2
fi

APP_PATH="$1"
PROFILE="$2"
OUTPUT_DIR="$(dirname "$APP_PATH")"
DMG_PATH="$OUTPUT_DIR/Atlas.dmg"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
hdiutil create -volname Atlas -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
echo "Notarized $DMG_PATH"
