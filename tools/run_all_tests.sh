#!/usr/bin/env bash
# Run every headless test suite (needs xvfb and Godot 3.5; assets imported: tools/import_assets.sh).
#   tools/run_all_tests.sh            fast, small window
#   SHOTS=1 tools/run_all_tests.sh    also write screenshots under tests/out/
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot3}"
# Start every run from default settings: earlier runs (the soak test, the menu tests) save options to the same file.
rm -f "$HOME/.local/share/godot/app_userdata/Storm Island/settings.cfg"
RES="${RES:-640x360}"
fail=0
run() {   # name extra-args (RES=WxH run ... for another window size)
  local name="$1"; shift
  local shots=""
  [ -n "${SHOTS:-}" ] && { mkdir -p "tests/out/$name"; shots="--shots=tests/out/$name"; }
  if timeout 300 xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --path . --resolution "${RES}" --audio-driver Dummy \
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
run accounts_test --no-bus --skip-menu
run perf_test --no-bus --skip-menu
run farm_test --no-bus --skip-menu
run vault_test --no-bus --skip-menu
run boss_test --no-bus --skip-menu
run zerobuild_test --no-bus --skip-menu
run weapons2_test --no-bus --skip-menu
run assist_test --no-bus --skip-menu
run gameplay_fixes_test --no-bus --skip-menu
run team_test --no-bus --skip-menu
run qol_test --no-bus --skip-menu
run a11y_test --no-bus --skip-menu
run quest_test --no-bus --skip-menu
run trap_test --no-bus --skip-menu
run reboot_test --no-bus --skip-menu
run fuel_test --no-bus --skip-menu
run wildlife_test --no-bus --skip-menu
run llama_test --no-bus --skip-menu
run weather_test --no-bus --skip-menu
run arsenal_test --no-bus --skip-menu
run revive_test --no-bus --skip-menu
run emote_test --no-bus --skip-menu
run menu_test
run social_test
run party_ui_test
run guard_test
run vault_test --no-bus --skip-menu
run boss_test --no-bus --skip-menu
run zerobuild_test --no-bus --skip-menu
run weapons2_test --no-bus --skip-menu
run assist_test --no-bus --skip-menu
run gameplay_fixes_test --no-bus --skip-menu
run pad_test
RES=844x390 run mobile_test --touch
exit $fail
