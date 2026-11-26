#!/bin/zsh
# Builds release binary and assembles an app bundle (ad-hoc signed).
# Usage: build-app.sh [output.app]   (default dist/Folio.app; tests use .build/test/Folio.app so a running copy is never replaced)
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Folio
APP=${1:-dist/Folio.app}
mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Folio "$APP/Contents/MacOS/Folio"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/Folio.icns ]] && cp Resources/Folio.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"
