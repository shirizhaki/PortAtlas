#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Regenerates the flat Packaging/AppIcon.icns from the Icon Composer document.
# build-app.sh compiles the document directly; this .icns is the fallback for
# builds without full Xcode and for the Xcode project target.
icon_work="$(mktemp -d)"
trap 'rm -rf "$icon_work"' EXIT
xcrun actool "$PWD/Packaging/AppIcon.icon" --compile "$icon_work" --platform macosx \
    --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist "$icon_work/partial.plist" >/dev/null
cp "$icon_work/AppIcon.icns" Packaging/AppIcon.icns
