#!/bin/bash
# Build DockBar.app. Compiles outside the Synology-synced tree to avoid sync churn.
# Usage: ./build.sh [--install]   (--install copies the app to /Applications)
set -euo pipefail
cd "$(dirname "$0")"

SCRATCH="$HOME/.cache/dockbar-build"
swift build -c release --scratch-path "$SCRATCH"

APP="DockBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SCRATCH/release/DockBar" "$APP/Contents/MacOS/DockBar"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/DockBar.app
    cp -R "$APP" /Applications/DockBar.app
    echo "Installed to /Applications/DockBar.app"
fi
