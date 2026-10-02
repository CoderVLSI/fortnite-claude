#!/usr/bin/env bash
# Debug APK -> build/android/StormIsland-debug.apk  (run tools/fetch_export_toolchain.sh first)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/android
xvfb-run -a "${GODOT:-godot3}" --path . --audio-driver Dummy --export-debug "Android" build/android/StormIsland-debug.apk
/opt/android-sdk/build-tools/33.0.2/apksigner verify --print-certs build/android/StormIsland-debug.apk 2>/dev/null | head -3 || true
ls -la build/android/StormIsland-debug.apk
