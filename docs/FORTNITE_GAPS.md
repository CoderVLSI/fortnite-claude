# Storm Island vs Fortnite Battle Royale: what is the same, what is added, what is still missing

Researched from the Fortnite wiki / Epic help pages (storm table, Reboot Vans, glider redeploy, accessibility "Visualize Sound
Effects", Turbo Building, weapon and item lists). Storm Island is an original game: this is a feature comparison, no Epic assets.

| Area | Fortnite | Storm Island |
|---|---|---|
| Match flow | Battle Bus, jump, freefall, glider, shrinking storm in many phases, last one standing | Same (Sky Ferry, 5 faster phases, 100 fighters) |
| **Glider redeploy** | Reopen the glider when falling from a height | **Added**: press jump while falling fast, 9 m or more up |
| Storm | Damage grows per phase (1% to 10% of max health) | 1 / 2 / 4 / 7 / 10 per second, scaled to the island |
| Building | Wall / floor / ramp / roof, edit, 3 materials | Same, Fortnite-style edit, auto material routing |
| **Turbo building** | Hold fire to keep placing | **Added** (Settings > Comfort) |
| Farming | Pickaxe, weak points | Pickaxe, **weak points** (double materials), buildings break piece by piece |
| Weapons | Pistol, SMG, AR, burst AR, shotgun, sniper, rocket launcher... | Pistol, SMG, AR, **Burst AR (new)**, pump + charge shotgun, bolt sniper, **Rocket Launcher (new, breaks buildings)**, Mythic variants |
| Explosives and traps | Grenade, shockwave, boogie bomb, stink bomb, traps, rockets | Grenade, shockwave, junk rift, **rockets, Boogie Bomb, Stink Bomb, Spike Trap, Proximity Mine** (all new); no grenade launcher yet |
| Mobility items | Bouncer, launch pad, jetpack, skateboard-like, rift | **Bouncer (new)**, jetpack, skateboard, Rift-to-Go, rifts, vehicles, slide, vault windows, mantle |
| Healing | Bandage, med kit, mini / big shield, slurp, chug jug | Same set |
| **Down but not out** | Squad modes: you go down, a teammate revives you | **Added**: duos / trios / squads, bleed-out 30 s, hold E to revive, bots revive you too |
| **Reboot Vans** | Bring a fallen teammate back with their card | **Added** (team modes): fallen team-mates leave a card, carry it to a van (vans in town and at named places), they drop back in with a pistol; bots can be rebooted too |
| Team modes | Duos, trios, squads | **Added**, no friendly fire, team win, ally tags |
| Pings | Ping enemy / loot / place | **Added** (T / middle mouse / map click / phone button) |
| Emotes | Emote wheel, music | **Added** (8 emotes with music, Locker slot) |
| Accessibility | Visualize sound effects, reticle options, HUD scale, toggle sprint... | **Added**: visualize sound effects, crosshair colour / size, toggle sprint / crouch, FOV, ADS sensitivity, low health / ammo warnings, rumble, button size; **colour-blind modes (3) with strength, HUD size slider** |
| Controller | Full gamepad | Auto-detected Xbox / PlayStation / Switch pads, remappable, menu navigation |
| Phone | Full touch HUD | Touch HUD, auto run, auto fire, edit button, ping, emote, 6-slot hotbar |
| Social | Friends, party, invites, queue together | LAN / IP party, friends (saved name + IP), invites, recent players, **party card + READY for members, leader presses PLAY to queue the whole party with one shared countdown, your party stands beside you in the lobby**; no internet matchmaking |
| Locker | Skins, pickaxes, back blings, gliders, contrails, emotes | All of those, plus Sprites as companions |
| Progression | Battle Pass, quests, XP | Level and stats per account (local), **12+ quests from Keepers (gold + XP)**; no battle pass |
| World life | NPCs, wildlife, vehicles with fuel, trains, weather | Boss, wild Sprites, **Keeper NPCs, chickens and boars (Roast Meat), vehicles with fuel + pumps, rain storms**. No trains |
| Loot | Chests, floor loot, vending machines, supply drops, llamas | All, **including Supply Llamas** (burst them for loot) |
| Players per match | 100 | 100 (humans + bots; the map is 1 km) |
| Servers | Dedicated, matchmaking, voice chat | LAN only, no voice |

## Still to do

1. A relay server so friends can play over the internet without port forwarding (needs a machine to host it; until then see
   "Playing over the internet" in the README: Tailscale / ZeroTier or forwarding UDP 7777).
2. A train that circles the island (a moving platform that carries riders).
3. A grenade launcher, boogie / stink bomb variants, a battle-pass style reward track.
4. Voice chat and dedicated servers.

## How it is tested

`tools/run_all_tests.sh` (headless suites), `tools/run_net_test.sh` (two-process LAN test), `tools/run_net_team_test.sh` (party ready-up and queue, Duos, knock-down, revive, reboot card + van across the network), and `tools/run_soak.sh`: exports the **native
Linux build** and lets a monkey player play whole matches in it (drops from the bus, glides, loots, fights, builds, heals, vaults,
emotes, pings, opens the map / inventory / menus, changes settings, in solo and team modes) and reports frame times, node growth
and any script errors.


## Fortnite-accurate numbers (this round)
* Weapons: per-rarity damage and reload tables, fire intervals and magazine sizes follow Fortnite (AR 30-36 dmg, mag 30; pump ~97-119 total, mag 4; SMG mag 30; sniper 95-116; rocket 105-121).
* Ammo: bigger pickup packs (light 60, medium 60, shells 12, heavy 10) and Fortnite carry caps (500 / 500 / 150 / 50).
* Building: wood 200, stone 300, metal 400 HP; material cap 500; pickaxe 20 on players, 75 on player-built pieces.
* Mantling: grab and pull yourself onto a ledge by jumping at it and holding forward; reach is about one storey (we allow up to 2.8 m).
* Anti-cheat v1 (`scripts/Guard.gd`): server-side speed, fire-rate, damage, range, flood and impersonation checks; damage is routed through the dedicated server (`docs/SERVER.md`).

## Map expansion, vaults and 100 players (Chapter 2 Season 2 as the reference)
* The island is now about 1 km across (was 720 m). Storm phases scale with it.
* Named places went from 20 to 28. Chapter 2 Season 2 counterparts (original names): THE BUREAU (the Agency), STEALTH STRONGHOLD, LAZY LAGOON (Lazy Lake), MURKY MIRE (Slurpy Swamp), MARKET STREET (Retail Row), SULFUR SPRINGS (Salty Springs), CRAFTY CORNER (Catty Corner), BRAMBLE HEDGES (Holly Hedges); the existing docks / farm / lighthouse / foundry / dunes cover Dirty Docks, Frenzy Farm, Lockie's, Steamy Stacks and Sweaty Sands.
* Vaults: a sealed concrete room at Iron Bunker, The Bureau and Stealth Stronghold. The steel door opens with a Vault Keycard dropped by that place's Warden (three bosses, each guarding a mythic); three mythic chests are inside. Door state is synced over the network. Vaults show on the big map.
* 100 fighters per match (humans + bots): bots far from every human send their pose 2-3 times a second instead of 10 to keep traffic down. Mobile runs 40 bots.
* Not done: a real lake (Loot Lake) and the Agency's helicopter ride.

## Overnight additions
* **Zero Build**: a toggle on the lobby mode card (ZERO BUILD / BUILDING ON). The host decides for the party and the choice reaches everyone; dedicated servers take `--zero-build` (`tools/run_server.sh --zero-build`). Build mode, build keys and phone build buttons all refuse with a message. Tested in `zerobuild_test`.
* **Four more weapons**: Tactical Shotgun (10 pellets, ~77+ per shot, 2 shots/s, 8 shells), Revolver (58-69, 6 rounds), Semi-Auto Sniper (63-75, 10 rounds), **Grenade Launcher** (lobs a bouncing grenade, 100-120 splash, 6 rounds, rare+). They borrow existing models, sounds and icons until the agents deliver dedicated ones (see `docs/ASSET_REQUESTS.md`). Tested in `weapons2_test`.
* Soak test with 100 fighters on the 1 km island (native Linux build, software rendering): full match to the victory screen, 0 script errors, no node growth.
* **Aim assist** for phones and controllers (Settings > Comfort, on by default): while you shoot or aim, the view eases onto an enemy that is already within ~7 degrees of the crosshair, in the open and in range. Tested in `assist_test`.
* **Weapon bloom**: spraying an automatic gun widens the cone (up to +90%); it settles in about half a second.
* Not done (deliberately): a battle-pass reward track, because every cosmetic is already unlocked and locking them would get in the way of testing with friends.
* **Storm pace** (Settings > Comfort, default 2.0): the circle waits and shrinks twice as long as before, so a 100-fighter match on the 1 km island lasts closer to a real match (set it to 1 for quick matches). The host's value counts.
* **Faces**: noses and mouths on every visible face, moustaches on pirates, cowboys and about half of the Ranger-suit fighters, a beard for the pirate. Knight, Unit 7 and Shadow Ninja keep a blank (covered) face. See `docs/faces.png`; `tests/face_shots.gd` re-renders it.
* **Bosses**: Voltra (Crafty Corner: mythic Charge Shotgun + Shockwave Launcher), Goldhand (The Bureau: mythic Drum Gun), Hookshot (Stealth Stronghold: mythic Grappler + rifle) and the Warden (Iron Bunker), each with 3-4 henchmen on the same team and a vault keycard. `tests/boss_test.gd`.
