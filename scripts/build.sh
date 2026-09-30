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
    cp .local-ai/manifest.json "$APP/Contents/Resources/local-ai/manifest.json"
    cp .local-ai/runtime/llama-completion .local-ai/runtime/LICENSE "$APP/Contents/Resources/local-ai/runtime/"
    cp -P .local-ai/runtime/*.dylib "$APP/Contents/Resources/local-ai/runtime/"
    cp .local-ai/models/qwen2.5-0.5b-instruct-q2_k.gguf "$APP/Contents/Resources/local-ai/models/"
fi
codesign --force --sign - "$APP"
printf 'Built: %s/%s\n' "$PWD" "$APP"
