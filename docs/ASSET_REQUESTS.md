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

## New weapons, ZERO BUILD and settings icons

- [x] `assets/icons/weapon_tactical_shotgun.png` 128x128, transparent. Short-barrel tactical pump, pistol grip, black and dark grey.
- [x] `assets/icons/weapon_revolver.png` 128x128, transparent. Six-shot revolver, long barrel, gunmetal and walnut grip.
- [x] `assets/icons/weapon_dmr.png` 128x128, transparent. Semi-auto marksman rifle, scope, box magazine, olive and black.
- [x] `assets/icons/weapon_grenade_launcher.png` 128x128, transparent. Drum-fed launcher, thick short barrel, orange and dark grey.
- [x] Mythic variants (optional, 128x128 transparent): `weapon_revolver_mythic`, `weapon_dmr_mythic`, `weapon_tactical_shotgun_mythic`,
  `weapon_grenade_launcher_mythic` (gold/purple glow versions, transparent).
- [x] `assets/ui/ui_zero_build.png` 128x128, transparent. Wooden wall panel with a diagonal red slash.
- [x] `assets/ui/ui_building.png` 128x128, transparent. The same wall panel without the slash.
- [x] `assets/ui/ui_aim_assist.png` 128x128, transparent. Crosshair with a magnet pulling toward a target.
- [x] `assets/ui/ui_storm_pace.png` 128x128, transparent. Purple storm cloud with a clock dial and a lightning bolt.
- [x] Place art for THE BUREAU, STEALTH STRONGHOLD, LAZY LAGOON, MURKY MIRE, MARKET STREET, SULFUR SPRINGS,
  CRAFTY CORNER, BRAMBLE HEDGES: **none exist** (`assets/ui/` still has no per-place banners), so nothing was added.

The new weapon icons use the same prompt text, angle and outline as the existing `weapon_*` icons but are transparent,
not on the blue slot tile (the existing weapon icons keep their tile). `ui_zero_build` is `ui_building` plus a slash and
the Mythic glow is added locally: both come from `tools/images/derive_icons.py` (no API call).

## Boss characters and their Mythic weapons

All transparent PNG, under 300 KB. Weapon icons use the same STYLE/angle as the other `weapon_*` icons; the Mythic
versions are the same gun in gold and purple with a soft glow (`tools/images/derive_icons.py mythic-glow`).

- [x] `assets/icons/weapon_drum_gun.png` 128x128. SMG with a big drum magazine, black body, gold trim and drum, tan foregrip.
- [x] `assets/icons/weapon_drum_gun_mythic.png` 128x128.
- [x] `assets/icons/weapon_shockwave_launcher.png` 128x128. Tube launcher, four glowing blue shock-coil rings, flared muzzle dish with a blue core.
- [x] `assets/icons/weapon_shockwave_launcher_mythic.png` 128x128.
- [x] `assets/icons/weapon_grappler.png` 128x128. Pistol-sized grapple launcher, two-pronged hook, red cable spool, red stripe, wooden grip.
- [x] `assets/icons/weapon_grappler_mythic.png` 128x128.
- [x] `assets/icons/weapon_charge_shotgun_mythic.png` 128x128 (did not exist before; the base `weapon_charge_shotgun.png` already did).
- [x] `assets/ui/ui_boss_voltra.png` 128x128. Bust: armoured engineer, dark blue helmet, glowing blue visor, electric sparks.
- [x] `assets/ui/ui_boss_goldhand.png` 128x128. Bust: tycoon in a black suit, gold-plated mask, gold glove, coins.
- [x] `assets/ui/ui_boss_hookshot.png` 128x128. Bust: infiltrator in a red hood and black mask, goggles pushed up, hook on a rope over the shoulder.
- [x] `assets/ui/ui_boss.png` 64x64. Skull wearing a gold crown on a red map pin (generic boss minimap marker).

## App icon redo

- [x] New app icon: gold-rimmed shield badge with a green island and a golden lightning bolt on a swirling purple/orange
  storm backdrop. Replaces the thin pickaxe-in-a-purple-ring icon. Files: `icon.png` (512x512, also the Godot window icon),
  `icon.ico` (Windows, 256/128/64/48/32/16), `assets/icons/launcher_main_192.png` (192x192),
  `assets/icons/launcher_fg_432.png` (432x432, transparent, emblem inside the central 58 % so round and squircle masks
  never crop it) and `assets/icons/launcher_bg_432.png` (432x432, backdrop only). All PNGs are under 300 KB.
  Built from two generated images (emblem on a magenta key, and the backdrop) composed locally, so the adaptive
  foreground/background pair matches the full icon exactly.

## Format fixes

- [x] `lobby_bg`, `victory_bg`, `eliminated_bg`, `loading_bg` converted from JPG to 256-colour PNG at 1280x720
  (all under 300 KB); the `.jpg` files were removed.
- [x] `logo.png` (was 1.1 MB), `launcher_fg_432.png` and `launcher_bg_432.png` palette-quantised to stay under 300 KB.

## Storm Island audio pass: vaults, Wardens, far-field, weapons (done)

Format of this batch: mono, **44.1 kHz**, 16-bit, peak -3 dBFS (3D-sound spec for Storm Island; the older sounds above are still 22.05 kHz).
Generated by `python3 tools/audio/generate_storm_island_sfx.py` (numpy only, deterministic; `--verify` measures the files).

- [x] `vault_unlock.wav` 1.6 s: keycard beep, heavy clunk, pneumatic hiss
- [x] `vault_door.wav` 2.2 s: steel door sliding up, servo grind, scrape, final thud, sub-bass
- [x] `keycard_pickup.wav` 0.6 s: bright chirp, plastic click, sparkle
- [x] `keycard_deny.wav` 0.5 s: two short low error buzzes
- [x] `vault_alarm.wav` 3.0 s: muffled distant klaxon, seamless loop, peak -9 dBFS (mid-quiet). Not named `*_loop`, so `Audio.gd` will not loop it by itself
- [x] `warden_spawn.wav` 2.0 s: low horn sting, one swell
- [x] `warden_down.wav` 1.5 s: body drop, armour clatter, rising shimmer
- [x] `distant_gunfire_a.wav`, `distant_gunfire_b.wav`, `distant_gunfire_c.wav` 1.2 s each: far-off firefights with lots of reverb
- [x] `bus_horn_far.wav` 1.5 s: distant two-tone bus horn, slight pitch fall
- [x] `players_left_ping.wav` 0.4 s: soft UI ping (play it with pitch changes for 75 / 50 / 25 / 10)
- [x] Weapon pass: `shot_smg.wav` and `shot_pistol.wav` were 0.8 s / 1.0 s, now cut to 0.15 s (50 ms fade, 44.1 kHz, -3 dBFS), overwritten in place. The assault rifle (0.18 s between shots), shotgun and sniper are unchanged. `shot_mythic.wav` (2 s, used for every mythic weapon) is unchanged.

## Audio pass: new weapons, revolver reload, UI toggles, heal-use loops (done)

Format: mono, **44.1 kHz**, 16-bit, peak -3 dBFS. Generated by `python3 tools/audio/generate_weapon_extras_sfx.py`
(numpy only, deterministic; `--verify` measures the files). `.wav.import` stubs are written next to each file.

- [x] `shot_tactical_shotgun.wav` 0.5 s: tight dry short-barrel blast, quick slide rack at the end
- [x] `shot_revolver.wav` 0.6 s: heavy ringing magnum crack, short metallic echo
- [x] `shot_dmr.wav` 0.7 s: sharp semi-auto crack, mid thump, short tail
- [x] `shot_grenade_launcher.wav` 0.6 s: hollow "thoonk" tube pop with a spring click
- [x] `reload_revolver.wav` 1.2 s: cylinder swings out, six rounds drop in, cylinder snaps shut
- [x] `grenade_launcher_bounce.wav` 0.3 s: dull metal bounce thud with a small second hop
- [x] `ui_toggle_on.wav` 0.15 s: soft switch click, rising
- [x] `ui_toggle_off.wav` 0.15 s: soft switch click, falling

### Heal / use sounds vs the real use times

`Fighter.gd` plays `consume_bandage` for bandage and medkit, `consume_potion` for every other drink, then `shield_up` /
`heal_up` when the use finishes. The one-shots are far shorter than the use times (22.05 kHz, unchanged):

| file | length | used for | use time |
|---|---|---|---|
| `consume_bandage.wav` | 1.2 s | bandage, medkit | 4 s / 10 s |
| `consume_potion.wav` | 1.0 s | shield potion, Chug Jug, other drinks | 5 s / 15 s |
| `shield_up.wav` | 1.0 s | on finish (shield) | - |
| `heal_up.wav` | 1.2 s | on finish (health) | - |

So two seamless loops were added (play them for the whole use, stop on finish or cancel; `Audio.gd` loops `*_loop`):

- [x] `consume_bandage_loop.wav` 2.0 s loop: rhythmic cloth rustle with tape tugs (bandage 4 s = 2 loops, medkit 10 s = 5)
- [x] `consume_potion_loop.wav` 2.0 s loop: steady glugs and small bubbles (shield potion 5 s, Chug Jug 15 s)

## Audio pass: boss characters, Drum Gun, Shockwave Launcher, Grappler, Charge Shotgun charge (done)

Format: mono, **44.1 kHz**, 16-bit, peak -3 dBFS. Generated by `python3 tools/audio/generate_boss_sfx.py`
(numpy only, deterministic; `--verify` measures the files). `.wav.import` stubs are written next to each file.

- [x] `shot_drum_gun.wav` 0.12 s: punchy, slightly boomy SMG round with a faint gold ping, tiny dry tail (fires ~9/s)
- [x] `reload_drum_gun.wav` 2.0 s: drum twisted out, rattling bullets, slapped back in, bolt rack
- [x] `shot_shockwave_launcher.wav` 0.8 s: deep "whump" with a rising electric zap
- [x] `shockwave_blast.wav` 1.2 s: sub-bass boom, sharp air crack, fading electric crackle
- [x] `reload_shockwave_launcher.wav` 1.8 s: heavy cartridge slid in, coils charge with a rising hum, "ready" tick
- [x] `grappler_fire.wav` 0.5 s: pneumatic "thwip" with a short cable zing
- [x] `grappler_hit.wav` 0.3 s: hook clank and a short scrape
- [x] `grappler_pull.wav` 1.0 s: seamless loop (motor whine with a periodic pitch swell, gear rumble, rope creak). It is not named `*_loop`, so `Audio.gd` will not loop it by itself: the code must restart it or set loop on the stream while the player is pulled
- [x] `grappler_release.wav` 0.3 s: cable going slack, soft metallic rattle
- [x] `charge_shotgun_charge.wav` 1.8 s: rising electric hum, peaks exactly at 1.8 s (cut it when fire is released early)
- [x] `boss_voltra_intro.wav` 2.5 s: low synth horn with crackling electricity (instrumental, no voice)
- [x] `boss_goldhand_intro.wav` 2.5 s: regal brass fanfare with a coin-chime shimmer
- [x] `boss_hookshot_intro.wav` 2.5 s: tense plucked strings, rope creak, short whoosh
- [x] `boss_defeated.wav` 2.0 s: heavy armour drop, rising shimmer, bright reward chime
