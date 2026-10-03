# 2D icon generator (OpenRouter)

`openrouter_generate.py` makes the game's 2D art (gun icons, ammo, healing items, materials and the app
icon) with whichever image model on [OpenRouter](https://openrouter.ai) is cheapest. Models and
sounds are separate: 3D models come from Blender scripts, audio from `tools/audio/`.

> **Status: untested against the live API.** It was written in a sandbox that could not reach
> openrouter.ai. The image-processing half (crop, resize, background removal) *was* tested offline.
> Expect to fix a small thing on the first real run, which is why `--test` exists.

## One-time setup

1. **Allow the host.** In the cloud environment menu (session title bar) > *Edit* > *Network access*,
   allow `openrouter.ai` (Custom > Allowed domains, keep the default package-manager list).
2. **Store the key as a secret** in the same screen, as an environment variable named
   `OPENROUTER_API_KEY`. Never paste it into chat or commit it.
3. **Start a new session.** Environment variables are read when a session starts, so an already-open
   session will not see the key or the network change.

Locally: `export OPENROUTER_API_KEY=...`. Needs `python3` and `ffmpeg`; nothing to `pip install`.

## Spend as little as possible

```bash
python3 tools/images/openrouter_generate.py --models            # image models, cheapest first
python3 tools/images/openrouter_generate.py --dry-run --group weapons   # prompts + count, costs nothing
python3 tools/images/openrouter_generate.py --test --cheapest   # ONE image (weapon_pistol): judge quality
```

Look at `assets/icons/weapon_pistol.png`. If it is good enough, continue; if not, pick another model
from `--models` and pass it with `--model <id>`. The cheapest model is not always usable, so test
before a batch.

Cost guards: at most `--max` images per run (default 12), existing files are skipped unless `--force`,
and `--dry-run` shows exactly what would be requested. Check your spend on OpenRouter's Activity page.

## Generate

```bash
python3 tools/images/openrouter_generate.py --cheapest --group weapons   # 6 gun/pickaxe icons
python3 tools/images/openrouter_generate.py --cheapest --group ammo
python3 tools/images/openrouter_generate.py --cheapest --group items     # healing + materials
python3 tools/images/openrouter_generate.py --cheapest weapon_sniper     # one asset, e.g. a redo
python3 tools/images/openrouter_generate.py --cheapest --force app_icon  # replaces icon.png
python3 tools/images/openrouter_generate.py --list                       # every asset name
```

| Group | Output | Size |
|---|---|---|
| `weapons` | `assets/icons/weapon_<pistol,smg,assault,shotgun,sniper,pickaxe>.png` | 128 |
| `ammo` | `assets/icons/ammo_<light,medium,shells,heavy>.png` | 128 |
| `items` | `assets/icons/heal_*.png`, `assets/icons/material_*.png` | 128 |
| `app` | `icon.png` (512) + `assets/icons/launcher_*` for Android | 512 / 192 / 432 |

Item icons are generated on a flat magenta background that ffmpeg turns transparent. Cheap models do
not follow "flat background" perfectly, so a pink fringe is possible: re-run that one asset with `--force`.
Icons are **not committed automatically**: check them, then `git add assets/icons icon.png`.

## After generating

* `tools/import_assets.sh` so Godot imports the PNGs (the `.import` cache is git-ignored).
* **App icon:** `python3 tools/images/openrouter_generate.py --wire-export` points the three
  `launcher_icons/*` lines of `export_presets.cfg` at the generated files (it skips any that don't exist).
  Then `tools/build_android.sh`. `icon.png` already feeds `project.godot`.
* **Gun icons are not shown in the game yet.** The hotbar and HUD currently draw their slots in code
  (`scripts/ui/Hotbar.gd`, `scripts/HUD.gd`), so wiring the icons in is a separate code change. Ask for it
  once you are happy with the art.

## Tweaking

Prompts live in the `ASSETS` table (and the shared `STYLE` string) at the top of the script. Edit a prompt,
re-run that one asset with `--force`. To add an asset, add one `add(name, group, prompt, size)` line.
