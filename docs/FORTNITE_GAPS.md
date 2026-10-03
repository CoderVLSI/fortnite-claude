# Storm Island vs Fortnite Battle Royale: what is the same, what is added, what is still missing

Researched from the Fortnite wiki / Epic help pages (storm table, Reboot Vans, glider redeploy, accessibility "Visualize Sound
Effects", Turbo Building, weapon and item lists). Storm Island is an original game: this is a feature comparison, no Epic assets.

| Area | Fortnite | Storm Island |
|---|---|---|
| Match flow | Battle Bus, jump, freefall, glider, shrinking storm in many phases, last one standing | Same (Sky Ferry, 5 faster phases, 50 fighters) |
| **Glider redeploy** | Reopen the glider when falling from a height | **Added**: press jump while falling fast, 9 m or more up |
| Storm | Damage grows per phase (1% to 10% of max health) | 1 / 2 / 4 / 7 / 10 per second, scaled to the island |
| Building | Wall / floor / ramp / roof, edit, 3 materials | Same, Fortnite-style edit, auto material routing |
| **Turbo building** | Hold fire to keep placing | **Added** (Settings > Comfort) |
| Farming | Pickaxe, weak points | Pickaxe, **weak points** (double materials), buildings break piece by piece |
| Weapons | Pistol, SMG, AR, burst AR, shotgun, sniper, rocket launcher... | Pistol, SMG, AR, **Burst AR (new)**, pump + charge shotgun, bolt sniper, **Rocket Launcher (new, breaks buildings)**, Mythic variants |
| Explosives | Grenade, shockwave, boogie bomb, rockets | Grenade, shockwave, junk rift, **rockets**; no boogie bomb / stink bomb / grenade launcher yet |
| Mobility items | Bouncer, launch pad, jetpack, skateboard-like, rift | **Bouncer (new)**, jetpack, skateboard, Rift-to-Go, rifts, vehicles, slide, vault windows, mantle |
| Healing | Bandage, med kit, mini / big shield, slurp, chug jug | Same set |
| **Down but not out** | Squad modes: you go down, a teammate revives you | **Added**: duos / trios / squads, bleed-out 30 s, hold E to revive, bots revive you too |
| Reboot Vans | Bring a fallen teammate back with their card | Not yet |
| Team modes | Duos, trios, squads | **Added**, no friendly fire, team win, ally tags |
| Pings | Ping enemy / loot / place | **Added** (T / middle mouse / map click / phone button) |
| Emotes | Emote wheel, music | **Added** (8 emotes with music, Locker slot) |
| Accessibility | Visualize sound effects, reticle options, HUD scale, toggle sprint... | **Added**: visualize sound effects, crosshair colour / size, toggle sprint / crouch, FOV, ADS sensitivity, low health / ammo warnings, rumble, button size; no colour-blind modes or HUD scale yet |
| Controller | Full gamepad | Auto-detected Xbox / PlayStation / Switch pads, remappable, menu navigation |
| Phone | Full touch HUD | Touch HUD, auto run, auto fire, edit button, ping, emote, 6-slot hotbar |
| Social | Friends, party, invites | LAN party, friends (saved name + IP), invites, recent players; no internet matchmaking |
| Locker | Skins, pickaxes, back blings, gliders, contrails, emotes | All of those, plus Sprites as companions |
| Progression | Battle Pass, quests, XP | Level and stats per account (local). **No quests / battle pass yet** |
| World life | NPCs, wildlife, vehicles with fuel, trains | Boss, wild Sprites, vehicles (no fuel). No NPCs, wildlife or trains yet |
| Loot | Chests, floor loot, vending machines, supply drops, llamas | All except llamas |
| Players per match | 100 | 50 (the map is 720 m) |
| Servers | Dedicated, matchmaking, voice chat | LAN only, no voice |

## Still to do (ranked)

1. Quests + NPCs (gold, XP, weekly challenges) and a simple battle-pass style track.
2. Reboot Vans and reboot cards in team modes.
3. Vehicle fuel and gas stations.
4. More explosives / traps: grenade launcher, boogie bomb, stink bomb, trap floors.
5. Colour-blind modes and a HUD scale slider.
6. Wildlife (chickens, boars) that drop healing meat.
7. A relay server so friends can play over the internet.
8. Llamas, a train, weather.

## How it is tested

`tools/run_all_tests.sh` (headless suites), `tools/run_net_test.sh` (two-process LAN test), and `tools/run_soak.sh`: exports the **native
Linux build** and lets a monkey player play whole matches in it (drops from the bus, glides, loots, fights, builds, heals, vaults,
emotes, pings, opens the map / inventory / menus, changes settings, in solo and team modes) and reports frame times, node growth
and any script errors.
