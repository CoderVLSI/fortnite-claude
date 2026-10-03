#!/usr/bin/env bash
# Two-process multiplayer test on localhost (a host and a client). Usage: tools/run_net_test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot3}"
pkill -f "[g]odot3 .*net_test" 2>/dev/null; sleep 1
mkdir -p /tmp/claude-0/net
rm -f /tmp/claude-0/net/*.json
args=(--path . --resolution 480x270 --audio-driver Dummy -s res://tests/net_test.gd)
timeout 420 xvfb-run -a "$GODOT" "${args[@]}" -- --no-capture --no-bus --skip-menu --role=host > /tmp/net_host.log 2>&1 &
HP=$!
sleep 6
timeout 420 xvfb-run -a "$GODOT" "${args[@]}" -- --no-capture --no-bus --skip-menu --role=client > /tmp/net_client.log 2>&1 &
CP=$!
wait $HP; hs=$?
wait $CP; cs=$?
grep -h "FAIL\|PASS\|NET_RESULT\|SCRIPT ERROR" /tmp/net_host.log /tmp/net_client.log | sort | uniq
echo "host exit $hs, client exit $cs"
[ $hs -eq 0 ] && [ $cs -eq 0 ]
