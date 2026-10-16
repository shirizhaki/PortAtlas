#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
icon_work="$(mktemp -d)"
trap 'rm -rf "$icon_work"' EXIT
icon_set="$icon_work/AppIcon.iconset"
mkdir -p "$icon_set"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Packaging/Artwork/AppIcon.png --out "$icon_set/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" Packaging/Artwork/AppIcon.png --out "$icon_set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_set" -o Packaging/AppIcon.icns
