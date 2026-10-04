# Asset requests (2D art)

Owner: image agent. Files live in `assets/icons/` and `assets/ui/`; the generator is `tools/images/openrouter_generate.py`
(see `tools/images/README.md`). **PNG only** (this Godot build cannot import JPG) and **each file under 300 KB**.
Icons are 128x128 transparent PNGs in a flat, bold-navy-outline style, readable at 24-48 px on a dark map.

## Vaults and keycards

- [x] `assets/ui/ui_vault.png` 128x128, transparent. Steel vault door, round wheel handle, orange accent (#FF5A1A).
- [x] `assets/ui/ui_keycard.png` 128x128, transparent. Orange keycard, black stripe, gold chip, tilted 15 degrees (HUD "VAULT KEYCARD x1").
- [x] `assets/icons/keycard.png` 256x256, transparent. Same card with a soft orange glow (inventory and pickups).
- [x] `assets/ui/ui_warden.png` 128x128, transparent. Gold and black armoured helmet with visor (boss map marker).

`ui_keycard` and `keycard` come from one generated image: the card is generated once at 256, `ui_keycard` is that card
downscaled to 128 (no glow), and `keycard` is the card centred at ~76 % of the canvas with an orange Gaussian glow
(Pillow: MaxFilter(9) + GaussianBlur(14) on the alpha) so the glow fades out inside the canvas.

## New places (THE BUREAU, STEALTH STRONGHOLD, LAZY LAGOON, MURKY MIRE, MARKET STREET, SULFUR SPRINGS, CRAFTY CORNER, BRAMBLE HEDGES)

- [x] Per-place banners: **none exist.** `assets/ui/` has only the shared lobby / victory / eliminated / loading
  backdrops and the logo, no per-place art, so nothing was added. (`docs/pois.png` and `docs/town.png` are
  documentation screenshots, not game assets.)

## Weapons, ammo, materials

- [x] Weapon icons: unchanged. Only damage and rarity numbers changed, not the weapons. (The icons were not compared
  side by side with the 3D models.)
- [x] Ammo and material icons: checked. None of them draws a quantity or any text, so the larger packs
  (light 60, medium 60, shells 12, heavy 10) need no icon change.

## Earlier batch (transparent item and UI icons, no inventory tile)

- [x] `heal_spike_trap`, `heal_proximity_mine`, `heal_boogie_bomb`, `heal_stink_bomb`, `heal_meat`, `heal_bouncer`,
  `weapon_rocket_launcher`, `weapon_burst_assault` in `assets/icons/`.
- [x] `ui_quest`, `ui_reboot_card`, `ui_llama`, `ui_fuel` in `assets/ui/`.
- [x] Gadget icons on the green slot tile: `heal_shockwave_grenade`, `heal_junk_rift`, `heal_jetpack`,
  `heal_skateboard`, `heal_rift_to_go`, `heal_grenade`, `heal_slurp_juice`, `heal_chug_jug`;
  `weapon_charge_shotgun`; `sprite_*` (earth, fire, water, duck, ghost, demon, king, dream, punk, aegis, lucky).

## Format fixes

- [x] `lobby_bg`, `victory_bg`, `eliminated_bg`, `loading_bg` converted from JPG to 256-colour PNG at 1280x720
  (all under 300 KB); the `.jpg` files were removed.
- [x] `logo.png` (was 1.1 MB), `launcher_fg_432.png` and `launcher_bg_432.png` palette-quantised to stay under 300 KB.
