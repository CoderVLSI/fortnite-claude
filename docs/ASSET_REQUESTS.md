# Assets still needed (hand-off to the audio and image agents)

The game plays silently / falls back to drawn shapes when a file is missing, so nothing breaks while these are pending.
Sounds are mono 22050 Hz 16-bit WAV in `assets/audio/` (same as the existing ones; `*_loop` names loop). Icons are 128x128 PNG
in `assets/icons/` on the usual transparent-with-tile style (see `tools/images/README.md`).

## Sounds (`assets/audio/<name>.wav`)

| name | length | what it is |
|---|---|---|
| `charge_start` | 0.3 s | click-and-whine as the Charge Shotgun starts charging |
| `charge_full` | 0.4 s | bright "ready" ping when the Charge Shotgun hits full charge |
| `shot_charge_shotgun` | 0.9 s | the Charge Shotgun's blast: heavier and more electric than the pump shotgun |
| `jetpack_thrust` | 0.35 s | one puff of a rocket-pack burst (played repeatedly while thrusting) |
| `board_mount` | 0.4 s | skateboard dropped and hopped onto: clack + wheels |
| `board_roll` | 0.5 s | skateboard wheels rolling over ground (played repeatedly while riding) |
| `shockwave_boom` | 1.2 s | deep concussive air-blast thump with a sweeping whoosh outward |
| `junk_rift_open` | 1.0 s | a cartoon portal tearing open high in the sky: rising crackle and hum |
| `junk_impact` | 2.0 s | something enormous slamming into the ground: crash, metal clang, debris |
| `rift_enter` | 0.9 s | stepping into a portal: rising whoosh and a sparkle, being flung skyward |
| `building_collapse` | 2.5 s | a wooden house collapsing: creaks, snapping beams, rumbling dust |
| `sprite_equip` | 0.6 s | a cute magical chime as a little spirit joins you |
| `sprite_levelup` | 0.8 s | an upbeat rising arpeggio, "level up" |
| `rain_loop` | 8 s loop | steady rain on grass and leaves, soft, no thunder |
| `thunder` | 3.5 s | a distant rolling thunderclap |

## Icons (`assets/icons/<name>.png`)

| name | what it shows |
|---|---|
| `heal_shockwave_grenade` | a round grenade in cyan/blue with a shock ring around it |
| `heal_junk_rift` | a purple swirling portal with an anvil falling out of it |
| `heal_jetpack` | a twin-tank red jetpack with orange flames |
| `heal_skateboard` | a cyan skateboard with yellow wheels, tilted |
| `heal_rift_to_go` | a small glowing violet portal ring, handheld gadget look |
| `weapon_charge_shotgun` | a chunky shotgun with glowing blue-yellow charge coils along the barrel |
| `sprite_earth` `sprite_fire` `sprite_water` `sprite_duck` `sprite_ghost` `sprite_demon` `sprite_king` `sprite_dream` `sprite_punk` `sprite_aegis` `sprite_lucky` | the eleven Sprite companions: round, glowing little ghosts with a face and tiny arms, coloured by element (earth green, fire orange, water blue, duck yellow with a bill, ghost pale white-blue, demon red with horns, king lilac with a gold crown, dream purple with stars, punk pink with a green mohawk, aegis teal with a halo, lucky gold with a green bow tie) |

Still pending from before: `heal_grenade`, `heal_slurp_juice`, `heal_chug_jug`, `gold_bar` (optional).

## Icons added by the main agent as plain placeholders (please redraw in the house style)

`heal_spike_trap`, `heal_proximity_mine`, `heal_boogie_bomb`, `heal_stink_bomb`, `weapon_rocket_launcher`, `weapon_burst_assault`, `heal_bouncer`.

## Status (updated)

Delivered by the audio agent: rain_loop, thunder, trap_set, spike_pop, mine_arm, mine_beep, boogie_pop, stink_hiss, llama_pop,
reboot_van, quest_accept, quest_complete, pump_fill, chicken_cluck, boar_grunt, out_of_fuel (all wired in the code).
Delivered by the image agent: heal_spike_trap, heal_proximity_mine, heal_boogie_bomb, heal_stink_bomb, heal_meat, heal_bouncer,
weapon_rocket_launcher, weapon_burst_assault, ui_quest, ui_reboot_card, ui_llama, ui_fuel.
3D models were redone in Blender (`ONLY=items blender -b -P tools/blender/generate_assets.py`) to look like their icons:
spike trap, proximity mine, boogie / stink / shockwave bombs, bouncer, roast meat, rift-to-go, junk rift (anvil), burst rifle,
charge shotgun, plus the grenade (ridged), round flask potions, chug jug, pistol colours and rocket launcher colours.
`tools/render_models.gd` renders any item model for a side-by-side check against its icon.

Update: the SMG, shotgun, sniper, assault rifle, burst rifle, charge shotgun, medkit and bandage models were redone too
(black bodies, thicker barrels, rolled-gauze bandage, case with latches and a red handle). The gun materials were renamed
(`gun_black`, `gun_gunmetal`, `gun_walnut`, ...) so Godot writes fresh `.material` files.

NOTE FOR THE IMAGE AGENT: this project's Godot build cannot import JPG files (`valid=false`, "Error loading image"). Keep
everything in `assets/ui/` and `assets/icons/` as PNG. To save space, quantise big backgrounds to a 256-colour PNG
(Pillow: `im.quantize(256, dither=Image.FLOYDSTEINBERG).save(path, optimize=True)`).


## Vaults and keycards (new)
* `assets/ui/ui_vault.png` (map marker for vault doors, same style as `ui_fuel.png`) and `assets/ui/ui_keycard.png` (HUD / pickup icon). The game falls back to a coloured dot until they exist.
* Optional 3D: `assets/models/keycard.glb` (credit-card sized, orange stripe) to replace the glowing cube; `vault_door.glb` to replace the grey box door.
