#!/bin/bash
# Builds a Developer ID–signed, notarized PortAtlas for direct download.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2. Notarization credentials saved as a keychain profile:
#      xcrun notarytool store-credentials PortAtlas --apple-id <Apple ID> --team-id <Team ID>
#
# Usage: Scripts/release.sh [keychain-profile]   (default profile: PortAtlas)
set -euo pipefail
cd "$(dirname "$0")/.."

profile="${1:-PortAtlas}"
identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
if [[ -z "$identity" ]]; then
    echo "No Developer ID Application certificate found in the keychain. See the setup notes in this script." >&2
    exit 1
fi

./Scripts/build-app.sh
app="build/PortAtlas.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"

# Hardened runtime and a secure timestamp are required for notarization.
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app"

dmg="build/PortAtlas-$version.dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "PortAtlas" -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg" >/dev/null
codesign --force --timestamp --sign "$identity" "$dmg"

xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

shasum -a 256 "$dmg" > "$dmg.sha256"
printf 'Notarized %s\n' "$dmg"
