#!/usr/bin/env bash
# Renders the Atlas brand SVGs into the Xcode asset catalog:
#   - AppIcon.appiconset  (dock / Finder icon, all macOS sizes)
#   - MenuBarIcon.imageset (template image for the menu bar)
# Requires: rsvg-convert (brew install librsvg).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ASSETS="$HERE/../Atlas/Assets.xcassets"
APPICON="$ASSETS/AppIcon.appiconset"
MENUBAR="$ASSETS/MenuBarIcon.imageset"

mkdir -p "$APPICON" "$MENUBAR"

echo "Rendering app icon PNGs..."
for px in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$px" -h "$px" "$HERE/atlas-app-icon.svg" -o "$APPICON/icon_${px}.png"
done

cat > "$APPICON/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "Rendering menu bar template PNGs..."
# 18pt menu bar icon at @1x/@2x/@3x.
rsvg-convert -w 18 -h 18 "$HERE/atlas-menubar-icon.svg" -o "$MENUBAR/menubar_18.png"
rsvg-convert -w 36 -h 36 "$HERE/atlas-menubar-icon.svg" -o "$MENUBAR/menubar_36.png"
rsvg-convert -w 54 -h 54 "$HERE/atlas-menubar-icon.svg" -o "$MENUBAR/menubar_54.png"

cat > "$MENUBAR/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "universal", "scale" : "1x", "filename" : "menubar_18.png" },
    { "idiom" : "universal", "scale" : "2x", "filename" : "menubar_36.png" },
    { "idiom" : "universal", "scale" : "3x", "filename" : "menubar_54.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
JSON

echo "Done. Wrote AppIcon + MenuBarIcon into $ASSETS"
