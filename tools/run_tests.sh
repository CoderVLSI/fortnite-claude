#!/usr/bin/env bash
# Regenerate assets (optional) and run the headless smoke test with screenshots.
#   tools/run_tests.sh            -> desktop profile, 1280x720
#   tools/run_tests.sh phone      -> mobile profile, 2400x1080, touch UI
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot3}"
mkdir -p tests/out
if [ "${1:-}" = "phone" ]; then
  RES=2400x1080; EXTRA="--mobile --touch"; OUT=tests/out/phone
else
  RES=1280x720; EXTRA=""; OUT=tests/out
fi
mkdir -p "$OUT"
xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --path . --resolution "$RES" --audio-driver Dummy \
  -s res://tests/smoke_test.gd -- --no-capture --no-bus --skip-menu $EXTRA --shots="$OUT"
