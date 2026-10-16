#!/bin/bash
set -euo pipefail
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
if (( ${sdk_version%%.*} < 26 )); then
    echo "PortAtlas requires the macOS 26 SDK or newer (Xcode 26+ or matching Command Line Tools). Runtime support starts at macOS 14." >&2
    exit 1
fi
swift --version
printf 'macOS SDK %s\n' "$sdk_version"
