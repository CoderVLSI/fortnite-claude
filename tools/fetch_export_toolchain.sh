#!/usr/bin/env bash
# Install everything needed to export from a locked-down box (e.g. a cloud sandbox where
# godotengine.org / GitHub releases are blocked but Docker Hub is reachable):
#   * Godot 3.5.2 export templates  -> ~/.local/share/godot/templates/3.5.2.stable
#   * Android SDK (build-tools, adb) -> $SDK_DIR (default /opt/android-sdk)
#   * debug keystore + Godot editor settings for Android signing
# They are taken from the public barichello/godot-ci:3.5.2 image by streaming its layers
# and keeping only the files we need. Needs: curl, python3, tar, a JDK (keytool/jarsigner).
set -euo pipefail

SDK_DIR="${SDK_DIR:-/opt/android-sdk}"
WORK="${WORK:-/tmp/godotci}"
IMAGE="barichello/godot-ci"
TAG="${TAG:-3.5.2}"
mkdir -p "$WORK"; cd "$WORK"

token() { curl -sS -m 30 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$IMAGE:pull" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])"; }

curl -sS -H "Authorization: Bearer $(token)" -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  "https://registry-1.docker.io/v2/$IMAGE/manifests/$TAG" > manifest.json
python3 -c "import json;[print(l['digest']) for l in json.load(open('manifest.json'))['layers']]" > layers.txt

while read -r digest; do
  echo "layer $digest"
  curl -sSL --fail -H "Authorization: Bearer $(token)" "https://registry-1.docker.io/v2/$IMAGE/blobs/$digest" \
    | tar -xz --wildcards -C "$WORK" '*share/godot/templates/*' '*android-sdk*' 2>/dev/null || true
done < layers.txt

mkdir -p "$HOME/.local/share/godot/templates"
cp -r "$WORK/root/.local/share/godot/templates/$TAG.stable" "$HOME/.local/share/godot/templates/"
# Distro builds of Godot report "<ver>.stable.custom_build" and look for that folder name.
ln -sfn "$HOME/.local/share/godot/templates/$TAG.stable" "$HOME/.local/share/godot/templates/$TAG.stable.custom_build"
[ -d "$SDK_DIR" ] || cp -r "$WORK/usr/lib/android-sdk" "$SDK_DIR"

mkdir -p "$HOME/.android" "$HOME/.config/godot"
[ -f "$HOME/.android/debug.keystore" ] || keytool -keyalg RSA -genkeypair -alias androiddebugkey \
  -keypass android -keystore "$HOME/.android/debug.keystore" -storepass android \
  -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
cat > "$HOME/.config/godot/editor_settings-3.tres" <<SETTINGS
[gd_resource type="EditorSettings" format=2]

[resource]
export/android/android_sdk_path = "$SDK_DIR"
export/android/adb = "$SDK_DIR/platform-tools/adb"
export/android/jarsigner = "$(command -v jarsigner)"
export/android/debug_keystore = "$HOME/.android/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
export/android/force_system_user = false
export/android/shutdown_adb_on_exit = true
SETTINGS
echo "toolchain ready (templates, Android SDK in $SDK_DIR, debug keystore)"
