# Rotorheads framework

Agents read this before editing. When you change a mechanic, update that mechanic's section in this file before you finish. The next agent learns from this file, not from your chat.

## How an agent works here

- Open new agents on this same project. `.cursor/rules/dcs-host.mdc` is always applied and points here.
- Stay inside the mechanic you were asked about. FARP warehouse and pad stock are not part of a CTLD task.
- Edit `mission/src/rh/*.lua`. From `mission/`, run `lua5.1 tests/run.lua` and then `lua5.1 tools/build.lua`. Commit `mission/dist/rotorheads.lua` with the source change.
- The owner replaces `C:\Users\Hill\Saved Games\DCS\Missions\Rotorheads\rotorheads.lua`, quits the mission to the main menu, and hosts `RH Manual.miz` again. Replacing the script does not reload a mission that is already running.
- Do not tell the owner to open the mission in the editor and save it unless they asked for an editor change. A save from the editor rewrites the FARP warehouse checkboxes.

## What runs

`rh_loader.lua` loads MOOSE, then `rotorheads.lua`. `tools/build.lua` concatenates the modules in this order, each inside its own `pcall`:

`util`, `config`, `core`, `dcs`, `world`, `logistics`, `outposts`, `factories`, `redair`, `lives`, `markers`, `convoy`, `livemap`, `ctld`, `csar`, `main`

`RH.start` in `main.lua` loads the save, restores the world, then starts logistics, outposts, factories, red air, paratroopers, lives, markers, convoy, CTLD, CSAR, and the live map. `RH.persistence.save` writes `Saved Games\DCS\rotorheads\campaign.lua`. Everything under `RH.state` is that file.

`server/Hooks/rh_hooks.lua` is the server hook. It cannot see mission globals through `net.dostring_in`. Mission calls go through `a_do_script`.

`mission/src/rh/dcs.lua` is the only module that calls the DCS API and MOOSE. Tests replace `RH.dcs` with `mission/tests/fake_dcs.lua`.

## Mission files

| File | Role |
| --- | --- |
| `Missions\Rotorheads\rotorheads.lua` | The campaign script the mission loads. |
| `Missions\Rotorheads\Moose_.lua` | MOOSE. Load it before the campaign script. |
| `Missions\RH Manual.miz` | The hosted mission. FARP warehouse flags live in its `warehouses` file. |
| `Saved Games\DCS\rotorheads\campaign.lua` | The war: FARPs, lives, factories, pad stock. |
| `Saved Games\DCS\rotorheads\world.lua` | Ground units and statics captured from the running mission. |

`static1-4` and `static1-5` are the editor FARP pads (unit ids 1000011 and 1000023). The mission editor names statics that way. They are heliports, not a script group. Their warehouse entries must keep `dynamicSpawn = true` and `unlimitedFuel`, `unlimitedMunitions`, and `unlimitedAircrafts` false. `mission/tools/patch_farp_warehouses.py` rewrites those two entries. Writing `0` with `setLiquidAmount` or `setItem` does not turn an unlimited warehouse into an empty one.

## Mechanics

### CTLD

`ctld.lua` builds the MOOSE CTLD menu from `config.lua` `troops`, `vehicles`, and `kits`. Every buildable group is a late-activated mission group named `RH_TPL_BLUE_*`. If a kit template is missing, `ctld.ensureKitTemplate` copies `RH_TPL_BLUE_HMMWV_TOW` so the crate still appears. Built vehicles are moved behind the helicopter by `ctld.placeBehind`. Crate counts are the normal counts in `config.lua`.

Not in this build, and not to be assumed: a one-crate test cost, an "all crates or one crate" menu, a flattened troop menu, or joining NASAMS and Roland pieces into one group.

### FARPs and logistics

Player FARPs are marked in the mission and spawned on a later start by `logistics.spawnBuilt` through `SPAWNSTATIC:InitFARP` (dynamic spawn on, hot start off). `RH_FARP_Bassel` in the current save is the logistics center at the tent, and it is not built.

The editor pads are separate. On the first start after this change, `logistics.syncPads` gives each pad named with type `FARP` 10 tons of jet fuel (`setLiquidAmount(0, 10000)`) and 40 of `weapons.missiles.AGM_114K`, `weapons.missiles.AGM_114L`, and `weapons.missiles.Vikhr_M`. The grant is stored on `RH.state.padStock[name]` with `granted = true`. Later starts write those saved numbers back. They do not add another 10 tons or another 40. Capture waits 25 seconds so the startup save cannot record an empty warehouse over the grant.

### MASH and CSAR

MASH separation is 16 km. A MASH zone in the editor is registered, and the tent is spawned beside it. CSAR uses `RH_TPL_DOWNED_PILOT` and the MOOSE CSAR module. Drop-off is at the MASH.

### The rest

Outposts, factories, red air, paratroopers, lives, map markers, convoys, and the live map each have their own module and start from `RH.start`. Red ground units in this build spawn from templates again. They are not saved and restored as live groups. That persistence was removed with the MASH rollback.

## Do not repeat

- Do not rebuild a FARP with `coalition.addGroup`. The dynamic-spawn list uses `coalition.addStaticObject` with `dynamicSpawn = true`, or the pad already saved in the mission.
- Do not zero a warehouse to make it limited.
- Do not respawn units from `persistence/Rotorheads.json` inside a `.miz`.
