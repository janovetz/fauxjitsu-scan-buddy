#!/bin/zsh
# Runs the tests. With only the Command Line Tools installed, plain `swift test` intermittently
# fails with "plugin for module 'TestingMacros' not found", so name the plugin's directory.
set -euo pipefail

cd "$(dirname "$0")/.."
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
