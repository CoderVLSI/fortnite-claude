#!/usr/bin/env bash
# Dedicated server test on localhost: starts a real server process and two clients. Usage: tools/run_server_test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot3}"
PORT="${PORT:-7790}"
TEST="${TEST:-server_test}"     # server_test (quick play) or server_room_test (private rooms)
pkill -f "[g]odot3 .*--server" 2>/dev/null; pkill -f "[g]odot3 .*server_test" 2>/dev/null; sleep 1
mkdir -p /tmp/claude-0/server
rm -f /tmp/claude-0/server/*.json
timeout 600 xvfb-run -a "$GODOT" --path . --resolution 320x180 --audio-driver Dummy -- --server --port=$PORT --no-capture --no-bus --bots=20 > /tmp/server_proc.log 2>&1 &
SP=$!
sleep 12
args=(--path . --resolution 480x270 --audio-driver Dummy -s res://tests/${TEST}.gd)
timeout 420 xvfb-run -a "$GODOT" "${args[@]}" -- --no-capture --no-bus --skip-menu --role=a --port=$PORT > /tmp/server_a.log 2>&1 &
AP=$!
timeout 420 xvfb-run -a "$GODOT" "${args[@]}" -- --no-capture --no-bus --skip-menu --role=b --port=$PORT > /tmp/server_b.log 2>&1 &
BP=$!
wait $AP; as=$?
wait $BP; bs=$?
sleep 3
grep -h "SERVER \|SERVER_RESULT" /tmp/server_proc.log | head -12
kill $SP 2>/dev/null
grep -h "FAIL\|PASS\|SERVER_RESULT\|ROOM_RESULT\|SCRIPT ERROR" /tmp/server_a.log /tmp/server_b.log | sort | uniq
echo "client a exit $as, client b exit $bs"
[ $as -eq 0 ] && [ $bs -eq 0 ]
