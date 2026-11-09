# Private Rotorheads-style DCS server

A from-scratch recreation of the gameplay of the [Rotorheads](https://rotorheads.fandom.com/wiki/Rotor_Heads_Wiki)
DCS World helicopter server, for running your own private server. It is not Rotorheads' code (that is not
public); it rebuilds the mechanics described in their wiki on top of the open-source
[MOOSE](https://github.com/FlightControl-Master/MOOSE) framework.

## What you get

**Campaign scripts** (`mission/`) for a persistent PvE war:

- **Factories** send reinforcement convoys by road to the areas REDFOR occupies. Destroy both buildings to slow
  them (red smoke marks the ruins), stop the Mi-26 repair flights, and hold the ruins with 4 ground units to
  capture the factory at the next restart.
- **Outposts** (three red containers) open a yellow contested zone when destroyed and launch a Mi-28 Havoc.
  Clear it and hold it with blue units: it turns blue, and after a hidden timer the outpost is captured and
  the front moves. If REDFOR holds it instead, it turns red and the outpost is repaired.
- **Enemy air**: Havocs when attack helicopters are spotted, MiG-29s / F-4s when blue fixed wing are detected,
  and paratroopers dropped after every restart.
- **Logistics** through MOOSE CTLD: troop squads sized per airframe, crates with real weights, sling loading,
  CH-47 dynamic cargo, repacking to repair and rearm. Each FARP has its own crate stock, while Logistics
  Centers and ships are unlimited.
- **Construction**: FARPs (9 crates, 15 NM apart, 5 NM from LCs), Logistics Centers (a FARP within 1 NM of
  an airfield), MASHes (4 crates, inside a blue zone, 16 km apart), blue outposts, and 30-minute "Fat Cow"
  repair points.
- **Lives and CSAR**: 3 lives on attack and fixed-wing airframes, unlimited on utility helicopters. A life is
  lost if you die, eject, or leave the aircraft away from a base, and comes back after 24 hours or when your
  pilot is rescued to a MASH or airfield. MASHes hold 30 patients; transport tasks empty them. Friendly
  fire costs a life and makes your weapons fail until you land at a FARP.
- **F10 marker commands**: `-smoke,<color>`, `-illumination`, `-wpzone`, `-farp?`, `-extract`.
- **Convoy escort side mission** for armed utility helicopters.
- **Persistence** across restarts, plus a live map export.

**Server hook** (`server/Hooks/rh_hooks.lua`): chat commands (`-time`, `-lives`, `-farps`, `-mash`,
`-help`), warnings before restart, an automatic restart every 5 hours, and an early restart when the
server has been empty for a while.

**Live map** (`livemap/`): a web app showing the front line, spotted threats (fading red blobs), enemy aircraft,
FARP crate stock, MASH capacity, downed pilots and the convoy. Without a server connected it shows a sample
Syria campaign.

## Run the live map locally

```bash
cd livemap
npm install
npm run dev          # http://localhost:4317
```

To show your own server, either:

- run it on the DCS machine and point it at the export:
  `LIVEMAP_STATE_FILE="C:\Users\YOU\Saved Games\DCS.dcs_serverrelease\rotorheads\livemap.json" npm run start`, or
- host it anywhere with `LIVEMAP_INGEST_TOKEN=<random secret>` set, and run the pusher on the DCS machine:
  `LIVEMAP_URL=https://your-map LIVEMAP_INGEST_TOKEN=<same secret> node livemap/scripts/push-state.mjs <path to livemap.json>`.
  Pushed state is kept in memory, so use one long-running server instance.

## Set up the DCS server

You need a Windows machine with the DCS World dedicated server, the Syria map (or any other map), and
optionally [SRS](http://dcssimpleradio.com/) for radios.

1. **Allow file access for persistence.** Edit `<DCS install>\Scripts\MissionScripting.lua` and comment out
   the sanitize lines so they read:
   ```lua
   --sanitizeModule('os')
   --sanitizeModule('io')
   --sanitizeModule('lfs')
   ```
   This lets mission scripts write files, so only run missions you trust. DCS updates overwrite this file, so
   redo it after every update.
2. **Install the hook.** Copy `server/Hooks/rh_hooks.lua` to
   `Saved Games\DCS.dcs_serverrelease\Scripts\Hooks\`. Add your UCID to `admins` if you want `-save`.
3. **Build the mission.** Follow [docs/MISSION_EDITOR.md](docs/MISSION_EDITOR.md): load `Moose_.lua` and
   `mission/dist/rotorheads.lua` with triggers, then place the named zones, statics and template groups.
4. **Configure the server.** Use `server/serverSettings.example.lua` as
   `Saved Games\DCS.dcs_serverrelease\Config\serverSettings.lua` (set a password to keep it private).
5. Start the server. Saves and the live map export are written to `Saved Games\DCS.dcs_serverrelease\rotorheads\`.
   Delete that folder to start a fresh campaign.

Tune any number (lives, restart time, crate counts, capture radii, airframe capacities) in
`mission/src/rh/config.lua`, or override it from the mission with `RH_CONFIG_OVERRIDES` without rebuilding.

## Develop the scripts

The campaign logic is plain Lua 5.1 (the DCS scripting version). All DCS and MOOSE calls go through
`mission/src/rh/dcs.lua`, so the rest is tested here against an in-memory fake.

```bash
cd mission
lua5.1 tests/run.lua      # 45 tests: factories, outposts, lives, logistics, convoy, markers, live map
lua5.1 tools/build.lua    # bundles src/rh/*.lua into dist/rotorheads.lua
```

| Path | Contents |
| --- | --- |
| `mission/src/rh/config.lua` | Every tunable value and template name |
| `mission/src/rh/factories.lua`, `outposts.lua`, `redair.lua` | The REDFOR side of the war |
| `mission/src/rh/logistics.lua`, `ctld.lua`, `csar.lua` | FARPs, LCs, MASH, crates, troops, rescue |
| `mission/src/rh/lives.lua`, `markers.lua`, `convoy.lua` | Lives, F10 marker commands, side mission |
| `mission/src/rh/livemap.lua`, `core.lua` | Live map export, events, scheduling, save files |
| `mission/src/rh/dcs.lua` | The only file that touches the DCS / MOOSE API |
| `server/` | Server hook and example server settings |
| `livemap/` | Next.js live map |

## Known gaps

- The DCS side has only been tested against the fake, not inside DCS. Expect a round of in-game fixes.
  Check `dcs.log` for lines starting with `[RH]`.
- Patreon slots, Discord registration codes, Combined Arms unit-control menus and the JTAC menu from the
  original server are not included. JTAC squads are plain troops; add a JTAC script if you want lasing.
- FARPs damaged by REDFOR cannot be repaired with repair crates yet.
