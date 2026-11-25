#!/bin/zsh
# Builds release binary and assembles dist/Folio.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Folio
APP=dist/Folio.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Folio "$APP/Contents/MacOS/Folio"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/Folio.icns ]] && cp Resources/Folio.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"
