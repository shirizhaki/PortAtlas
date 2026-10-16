#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

test_options=(--disable-xctest)
# Some Command Line Tools versions don't automatically locate the bundled
# Swift Testing macro plugin. Resolve it from the selected toolchain.
developer_dir="$(xcode-select -p)"
if [[ "$developer_dir" == */CommandLineTools ]]; then
    compiler_dir="$(dirname "$(xcrun --find swiftc)")"
    testing_plugin="$compiler_dir/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
    if [[ -f "$testing_plugin" ]]; then
        test_options+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
    fi
fi
swift test "${test_options[@]}" "$@"
