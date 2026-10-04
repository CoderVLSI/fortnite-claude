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
