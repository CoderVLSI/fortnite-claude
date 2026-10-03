#!/usr/bin/env bash
# Run every headless test suite (needs xvfb and Godot 3.5; assets imported: tools/import_assets.sh).
#   tools/run_all_tests.sh            fast, small window
#   SHOTS=1 tools/run_all_tests.sh    also write screenshots under tests/out/
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot3}"
RES="${RES:-640x360}"
fail=0
run() {   # name extra-args
  local name="$1"; shift
  local shots=""
  [ -n "${SHOTS:-}" ] && { mkdir -p "tests/out/$name"; shots="--shots=tests/out/$name"; }
  if timeout 300 xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --path . --resolution "$RES" --audio-driver Dummy \
      -s "res://tests/${name}.gd" -- --no-capture "$@" $shots > "/tmp/${name}.log" 2>&1; then
    printf "  %-14s ok   %s\n" "$name" "$(grep -E '_RESULT' /tmp/${name}.log | tail -1)"
  else
    printf "  %-14s FAIL\n" "$name"; grep -E "FAIL|SCRIPT ERROR|  - " "/tmp/${name}.log" | head -8; fail=1
  fi
}
run smoke_test --no-bus --skip-menu
run bus_test --skip-menu
run movement_test --no-bus --skip-menu
run vehicle_test --no-bus --skip-menu
run build_test --no-bus --skip-menu
run poi_test --no-bus --skip-menu
run scope_test --no-bus --skip-menu
run inventory_test --no-bus --skip-menu
run mechanics_test --no-bus --skip-menu
run edit_test --no-bus --skip-menu
run vending_test --no-bus --skip-menu
run sprite_test --no-bus --skip-menu
run structure_test --no-bus --skip-menu
run gadget_test --no-bus --skip-menu
run highrise_test --no-bus --skip-menu
run skin_test --no-bus --skip-menu
run menu_test
exit $fail
