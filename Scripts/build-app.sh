#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/check-toolchain.sh
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="build/PortAtlas.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/PortAtlas" "$app_dir/Contents/MacOS/PortAtlas"
# Remove local source paths carried by debug symbols before packaging.
strip -S "$app_dir/Contents/MacOS/PortAtlas"
cp Packaging/Info.plist "$app_dir/Contents/Info.plist"
cp Packaging/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp LICENSE "$app_dir/Contents/Resources/LICENSE"
cp ThirdPartyNotices/WhatPort-LICENSE.txt "$app_dir/Contents/Resources/WhatPort-LICENSE.txt"
cp Packaging/PrivacyInfo.xcprivacy "$app_dir/Contents/Resources/PrivacyInfo.xcprivacy"
if command -v codesign >/dev/null; then
    codesign --force --sign - "$app_dir"
fi
printf 'Built %s\n' "$app_dir"
