#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release -j 2
APP="dist/Offline Lens.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/OfflineLens "$APP/Contents/MacOS/OfflineLens"
cp scripts/Info.plist "$APP/Contents/Info.plist"
if [ -f .local-ai/manifest.json ] && [ -x .local-ai/runtime/llama-completion ]; then
    mkdir -p "$APP/Contents/Resources/local-ai/runtime" "$APP/Contents/Resources/local-ai/models"
    cp .local-ai/runtime/llama-completion .local-ai/runtime/LICENSE "$APP/Contents/Resources/local-ai/runtime/"
    cp -P .local-ai/runtime/*.dylib "$APP/Contents/Resources/local-ai/runtime/"
    python3 scripts/bundle-local-ai.py "$APP/Contents/Resources/local-ai"
fi
codesign --force --sign - "$APP"
printf 'Built: %s/%s\n' "$PWD" "$APP"
