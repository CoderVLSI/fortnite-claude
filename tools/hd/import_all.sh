#!/usr/bin/env bash
# Import every hd/models/*.glb with embedded materials (two editor passes: first creates the .import files, then they are patched
# and re-imported).   tools/hd/import_all.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
tools/import_assets.sh 240 | tail -1
changed=0
for f in hd/models/*.glb.import; do
  [ -e "$f" ] || continue
  if grep -q "^materials/location=1" "$f"; then
    sed -i 's/^materials\/location=1/materials\/location=0/; s/^materials\/storage=1/materials\/storage=0/; s/^materials\/keep_on_reimport=true/materials\/keep_on_reimport=false/' "$f"
    p=$(grep '^path=' "$f" | sed 's/path="res:\/\/\(.*\)"/\1/')
    base="${p%.scn}"
    rm -f "$base".* 2>/dev/null
    changed=$((changed + 1))
  fi
done
rm -f hd/models/*.material
if [ "$changed" -gt 0 ]; then tools/import_assets.sh 240 | tail -1; fi
echo "hd models re-imported with embedded materials: $changed"
