#!/bin/zsh
# Regenerates App/AppIcon.icns from the mascot. Only needed when the mascot changes.
set -euo pipefail

cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/AppIcon.iconset"
swiftc -o "$work/make-icon" scripts/make-icon/main.swift Sources/ScanButton/BuddyMascot.swift
"$work/make-icon" "$work/AppIcon.iconset"
iconutil -c icns -o App/AppIcon.icns "$work/AppIcon.iconset"
echo "Wrote App/AppIcon.icns"
