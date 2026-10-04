#!/usr/bin/env bash
# Run N dedicated Storm Island servers (one process per match, consecutive UDP ports).
#   tools/run_server.sh [-n COUNT] [-p BASE_PORT] [-b BOTS] [--zero-build]   (default: 2 instances, port 7777, 30 bots)
# Uses build/linux/StormIsland.x86_64 if present (tools/run_server.sh --export builds it), else godot3 --path .
# Needs: UDP ports BASE..BASE+COUNT-1 (game) and BASE+1000.. (status probe) open in the firewall.
set -uo pipefail
cd "$(dirname "$0")/.."
COUNT=2; PORT=7777; BOTS=30; EXTRA=""
BIN="${BIN:-build/linux/StormIsland.x86_64}"
while [ $# -gt 0 ]; do
  case "$1" in
    -n) COUNT="$2"; shift 2;;
    -p) PORT="$2"; shift 2;;
    -b) BOTS="$2"; shift 2;;
    --zero-build) EXTRA="--zero-build"; shift;;
    --export)
      mkdir -p build/linux
      xvfb-run -a "${GODOT:-godot3}" --path . --audio-driver Dummy --export "Linux/X11" "$BIN" || exit 1
      echo "exported $BIN"; exit 0;;
    *) echo "unknown option $1"; exit 2;;
  esac
done
if [ -x "$BIN" ]; then CMD=("$BIN"); else CMD=("${GODOT:-godot3}" --path .); fi
pids=()
trap 'kill "${pids[@]}" 2>/dev/null; exit 0' INT TERM
for ((i = 0; i < COUNT; i++)); do
  # Each instance restarts itself if it ever crashes; the lobby returns to idle after every match.
  ( while true; do
      xvfb-run -a "${CMD[@]}" --audio-driver Dummy --resolution 320x180 -- --server --port=$((PORT + i)) --instance=$i --bots="$BOTS" $EXTRA
      echo "instance $i exited, restarting in 3 s"; sleep 3
    done ) &
  pids+=($!)
  echo "instance $i -> UDP $((PORT + i)) (status $((PORT + i + 1000)))"
done
wait
