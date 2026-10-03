#!/usr/bin/env bash
# Export the native Linux build and let a monkey player play it for a while (see tests/soak_test.gd).
#   tools/run_soak.sh [minutes] [team size] [speed]
# Prints the soak summary and how many script errors / warnings the log contains. Log: /tmp/soak_<team>.log
set -uo pipefail
cd "$(dirname "$0")/.."
MIN="${1:-4}"; TEAM="${2:-1}"; SPEED="${3:-4}"
mkdir -p build/linux-test
if [ -z "${SKIP_EXPORT:-}" ]; then
  xvfb-run -a "${GODOT:-godot3}" --path . --audio-driver Dummy --export-debug "Linux Test" build/linux-test/StormIsland-test.x86_64 > /tmp/soak_export.log 2>&1
fi
LOG="/tmp/soak_${TEAM}.log"
timeout 1500 xvfb-run -a -s "-screen 0 960x540x24" build/linux-test/StormIsland-test.x86_64 --resolution 960x540 --audio-driver Dummy \
  -s res://tests/soak_test.gd -- --no-capture --minutes="$MIN" --team="$TEAM" --speed="$SPEED" > "$LOG" 2>&1
echo "exit code: $?"
grep -E "^SOAK" "$LOG" | tail -30
echo "script errors: $(grep -c 'SCRIPT ERROR' "$LOG")   engine errors: $(grep -c '^ERROR' "$LOG")   crashes: $(grep -c handle_crash "$LOG")"
grep -E "SCRIPT ERROR|^ERROR" -A1 "$LOG" | head -40
