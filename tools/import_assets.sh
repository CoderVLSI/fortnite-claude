#!/usr/bin/env bash
# Import new/changed assets (.glb models, audio, fonts) with the Godot editor, headless.
# `--editor --quit` exits before the filesystem scan finishes, so let the editor run and stop it
# once the .import cache has stopped growing.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot3}"
WAIT="${1:-150}"
setsid xvfb-run -a "$GODOT" --path . --editor --audio-driver Dummy > /tmp/godot_import.log 2>&1 &
PID=$!
last=-1; stable=0
for ((i = 0; i < WAIT; i += 3)); do
  sleep 3
  n=$(find .import -type f 2>/dev/null | wc -l)
  if [ "$n" = "$last" ]; then stable=$((stable + 1)); else stable=0; fi
  last=$n
  if [ "$stable" -ge 6 ]; then break; fi      # unchanged for ~18 s -> done
done
kill -- -"$PID" 2>/dev/null || kill "$PID" 2>/dev/null
sleep 1
echo "imported: $(ls .import | grep -c '\.scn') scenes, $(ls .import | wc -l) cache files"
