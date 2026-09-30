#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release -j 2
APP="dist/Offline Lens.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/OfflineLens "$APP/Contents/MacOS/OfflineLens"
cp scripts/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf 'Built: %s/%s\n' "$PWD" "$APP"
