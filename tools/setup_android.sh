#!/usr/bin/env bash
# One-time helper for exporting the Android build from your own machine.
# Creates a debug keystore and prints the Godot Editor Settings to fill in.
set -euo pipefail
cd "$(dirname "$0")/.."

KEYSTORE="${KEYSTORE:-$HOME/.android/debug.keystore}"
mkdir -p "$(dirname "$KEYSTORE")"
if [ ! -f "$KEYSTORE" ]; then
  keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
    -keystore "$KEYSTORE" -storepass android \
    -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
fi

cat <<MSG

Debug keystore: $KEYSTORE

In Godot 3.5: Editor > Editor Settings > Export > Android set
  Android Sdk Path   -> your Android SDK (needs build-tools + platform-tools)
  Debug Keystore     -> $KEYSTORE
  Debug Keystore User-> androiddebugkey
  Debug Keystore Pass-> android
Then: Editor > Manage Export Templates > download 3.5.2, and run
  godot --path . --export-debug "Android" build/android/StormIsland.apk
  adb install -r build/android/StormIsland.apk
MSG
