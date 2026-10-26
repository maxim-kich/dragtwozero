#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ICON_TMP=$(mktemp -d)
trap 'rm -rf "$ICON_TMP"' EXIT
for variant in light dark; do
  swift scripts/render-icon.swift "assets/AppIcon/$variant.svg" "$ICON_TMP/$variant.png"
  sips -z 1024 1024 "$ICON_TMP/$variant.png" --out "assets/AppIcon/$variant.png" >/dev/null
  ICONSET="$ICON_TMP/$variant.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "assets/AppIcon/$variant.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "assets/AppIcon/$variant.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "assets/AppIcon/$variant.icns"
done
