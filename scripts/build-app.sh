#!/bin/zsh
# Builds release binary and assembles an app bundle (ad-hoc signed).
# Usage: build-app.sh [output.app]   (default dist/Fylladio.app; tests use .build/test/Fylladio.app so a running copy is never replaced)
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Fylladio
APP=${1:-dist/Fylladio.app}
mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Fylladio "$APP/Contents/MacOS/Fylladio"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/Fylladio.icns ]] && cp Resources/Fylladio.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"
