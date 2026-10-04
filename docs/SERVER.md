# Running a Storm Island dedicated server

One server process = one match at a time (up to 16 humans + bots). Run several instances for more concurrent matches.

## Quick start (any Linux box with xvfb)
```
tools/run_server.sh --export          # builds build/linux/StormIsland.x86_64 (needs export templates)
tools/run_server.sh -n 4 -p 7777      # 4 instances on UDP 7777..7780
```
Without an export, the script falls back to `godot3 --path .`.

## Firewall
Open **UDP** `BASE..BASE+N-1` (game) and `BASE+1000..BASE+1000+N-1` (status probe used for Quick Play / ping).

## Docker / systemd
`Dockerfile.server` wraps the exported binary; `tools/deploy/storm-island.service` is a systemd unit with auto-restart.

## Pointing clients at it
* Menu → PARTY → ONLINE: type `host[:port][+count]` (e.g. `play.example.com:7777+4`) and press SAVE, or
* ship `server.cfg` next to the game (`res://server.cfg`): `[server]` / `addr="play.example.com:7777+4"`.
Server and client **must run the same build** (`Net.VERSION`, currently `storm-island-net-1`).

## Rooms
* QUICK PLAY joins the emptiest public lobby; the match starts when everyone is ready or after the wait timer.
* CREATE ROOM gives a code (letter + 4 characters); friends enter it with JOIN CODE; the room leader presses START MATCH.

## Authority (anti-cheat v1)
The server validates what clients report: shot rate and range, damage caps, movement speed, pickups, build rate and RPC flood
(see `Net.gd` / `World.net_damage`). A client that breaks the limits is dropped and logged as `SERVER CHEAT`.
This stops casual cheating; a determined cheater still needs real server-side simulation (planned).
