#!/bin/zsh
# Builds Fauxjitsu Scan Buddy.app. Usage: scripts/build-app.sh [--install]
# --install copies it to ~/Applications and launches it.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product ScanButton
binary="$(swift build -c release --show-bin-path 2>/dev/null | tail -1)/ScanButton"

app=".build/Fauxjitsu Scan Buddy.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/ScanButton"
cp App/Info.plist "$app/Contents/Info.plist"
cp App/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
    target="$HOME/Applications/Fauxjitsu Scan Buddy.app"
    pkill -x ScanButton 2>/dev/null || true
    while pgrep -x ScanButton >/dev/null; do sleep 0.1; done
    mkdir -p "$HOME/Applications"
    # The app was called ScanButton before it was renamed.
    rm -rf "$HOME/Applications/ScanButton.app" "$target"
    cp -R "$app" "$target"
    # LaunchServices can briefly refuse a just-replaced app (error -600).
    for attempt in 1 2 3 4 5; do
        open "$target" && break
        [[ $attempt == 5 ]] && exit 1
        sleep 1
    done
    echo "Installed and launched $target"
fi
