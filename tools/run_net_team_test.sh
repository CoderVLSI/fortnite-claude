#!/usr/bin/env bash
# Two-process party + team test on localhost: ready-up, shared queue countdown, Duos, knock-down / revive / reboot card + van
# across the network. Usage: tools/run_net_team_test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot3}"
pkill -f "[g]odot3 .*net_team_test" 2>/dev/null; sleep 1
mkdir -p /tmp/claude-0/netteam
rm -f /tmp/claude-0/netteam/*.json
args=(--path . --resolution 480x270 --audio-driver Dummy -s res://tests/net_team_test.gd)
timeout 420 xvfb-run -a "$GODOT" "${args[@]}" -- --no-capture --no-bus --skip-menu --role=host > /tmp/netteam_host.log 2>&1 &
HP=$!
sleep 6
timeout 420 xvfb-run -a "$GODOT" "${args[@]}" -- --no-capture --no-bus --skip-menu --role=client > /tmp/netteam_client.log 2>&1 &
CP=$!
wait $HP; hs=$?
wait $CP; cs=$?
grep -h "FAIL\|PASS\|TEAM_RESULT\|SCRIPT ERROR" /tmp/netteam_host.log /tmp/netteam_client.log | sort | uniq
echo "host exit $hs, client exit $cs"
[ $hs -eq 0 ] && [ $cs -eq 0 ]
