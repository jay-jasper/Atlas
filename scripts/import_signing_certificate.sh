#!/usr/bin/env bash
set -euo pipefail

: "${CERTIFICATE_P12:?APPLE_CERTIFICATE_P12 secret is required}"
: "${CERTIFICATE_PASSWORD:?APPLE_CERTIFICATE_PASSWORD secret is required}"

KEYCHAIN_PATH="$RUNNER_TEMP/atlas-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
echo "$CERTIFICATE_P12" | base64 --decode > "$RUNNER_TEMP/atlas-signing.p12"
security import "$RUNNER_TEMP/atlas-signing.p12" -P "$CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security list-keychain -d user -s "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

if [[ -n "${APPLE_PROVISIONING_PROFILE:-}" ]]; then
  PROFILE_PATH="$RUNNER_TEMP/atlas.provisionprofile"
  PROFILE_PLIST="$RUNNER_TEMP/atlas-provisioning.plist"
  PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
  mkdir -p "$PROFILE_DIR"
  echo "$APPLE_PROVISIONING_PROFILE" | base64 --decode > "$PROFILE_PATH"
  security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"
  PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$PROFILE_PLIST")"
  cp "$PROFILE_PATH" "$PROFILE_DIR/$PROFILE_UUID.provisionprofile"
fi
