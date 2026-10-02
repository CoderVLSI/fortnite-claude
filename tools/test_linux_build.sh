#!/usr/bin/env bash
# Export a standalone Linux binary (with the smoke test packed in) and run the screenshot
# test from the *exported* build instead of the editor. Screenshots -> tests/out/linux-build/
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/linux-test tests/out/linux-build
xvfb-run -a "${GODOT:-godot3}" --path . --audio-driver Dummy --export-debug "Linux Test" build/linux-test/StormIsland-test.x86_64
xvfb-run -a -s "-screen 0 1280x720x24" build/linux-test/StormIsland-test.x86_64 --resolution 1280x720 \
  --audio-driver Dummy -s res://tests/smoke_test.gd -- --no-capture --no-bus --skip-menu --shots="$PWD/tests/out/linux-build"
