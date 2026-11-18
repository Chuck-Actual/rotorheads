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

`ctld.lua` builds the MOOSE CTLD menu from `config.lua` `troops`, `vehicles`, and `kits`. Every buildable group is a late-activated mission group named `RH_TPL_BLUE_*`. If a kit template is missing, `ctld.ensureKitTemplate` copies `RH_TPL_BLUE_HMMWV_TOW` so the crate still appears. Built vehicles are moved behind the helicopter by `ctld.placeBehind`.

`config.testVehicleCrates` is `1` while ground units are being tested. The real count stays on each vehicle. Set the override to `nil` to use those counts again. Logistics Centers and ships have unlimited crates. General supply is loaded only there. Its template is `RH_TPL_BLUE_SUPPLY`, separate from the FARP kit. Build does not accept general supply, and it does not mark a FARP. Only the FARP Crate kit marks a FARP. After general supply is dropped at a FARP, park within 150 m of that FARP tent and use F10 > CTLD > **Return crates to tent** (also under Manage Crates). The check uses the tent, not the pad. Each general-supply crate adds 5 to that FARP. Those crates can then be drawn back out at the tent as ground-unit crates.

Not in this build, and not to be assumed: an "all crates or one crate" menu, a flattened troop menu, or joining NASAMS and Roland pieces into one group.

### FARPs and logistics

Player FARPs are marked in the mission and spawned on a later start by `logistics.spawnBuilt` through `SPAWNSTATIC:InitFARP` (dynamic spawn on, hot start off). `RH_FARP_Bassel` in the current save is the logistics center at the tent, and it is not built.

The editor pads are separate. On the first start after this change, `logistics.syncPads` gives each pad named with type `FARP` 10 tons of jet fuel (`setLiquidAmount(0, 10000)`) and 40 of `weapons.missiles.AGM_114K`, `weapons.missiles.AGM_114L`, and `weapons.missiles.Vikhr_M`. The grant is stored on `RH.state.padStock[name]` with `granted = true`. Later starts write those saved numbers back. They do not add another 10 tons or another 40. Capture waits 25 seconds so the startup save cannot record an empty warehouse over the grant.

`logistics.discoverEditorPads` also gives each of those pads a crate stock, without rebuilding the pad. The map label is a name from `config.farp.names` (COPPERHEAD, RATTLESNAKE, MUSTANG, LONGBOW, DAGGER, OUTLAW, WARHORSE, SWITCHBLADE, IRONCLAD, GHOST), picked at random and not reused while that FARP exists. A FARP already in the save gets one of those names too, unless it already has one. Decommissioning it removes the record and frees the name. The label sits just east of the tent, white on a dark box, for blue: the name, then `Crates: N`. The mark is created once and its text is updated in place, including for a FARP that was already in the mission. It stays up. The blue load circle is separate and lasts 60 seconds. CTLD > Show logistics zones draws those circles again and registers the same circle as the CTLD load zone. A logistics center uses a 500 m circle. A FARP tent uses 150 m. A saved `loadZoneReady` flag does not skip that zone on the next launch. A new pad starts at 0. `RH_FARP_Bassel` stays the logistics center and reads `Crates: unlimited`.

A script-built FARP that lands within 400 m of an editor pad or tent is a duplicate. `logistics.dropStackedFarps` deletes that copy, including `FARP 01` and its tent, depots, and Humvee, and the editor pad keeps the crate count. A marked FARP in an empty field is still spawned.

The editor tent is a CTLD load zone. Troops can always be picked up there. Ground-unit crates can be picked up only while the FARP stock covers them. Hovering into the zone does not load crates. `logistics.equipEditorFarps` parks the missing Humvee by that tent and writes the pad's fuel and missile grant, so rearm and defuel work at the FARP that was already in the mission.

The CH-47 loads and unloads crates with the rearm/refuel cargo menu, which is what changes the aircraft weight. CTLD Get Crates only puts the crates on the ground for that helicopter. UH helicopters still load and drop with CTLD. Return crates to tent counts the crates on the ground after that unload. General supply is not taken into the tent until that command.

### MASH and CSAR

A MASH exists only after a player builds the 6-crate MASH kit. An editor zone named `MASH` is not registered. On start, `logistics.spawnPlayerMashes` drops every saved MASH that a player did not build, deletes the hospital tents (including the one the old zone left at the north end of the airfield), and spawns tents only for player MASHes. The logistics tent stays. The world save does not keep hospital tents, because `logistics` spawns them from `RH.state.mashes`.

The only build check is distance. `logistics.validateMashSite` allows the build when the point is within 500 m of a FARP or Logistics Center, including that site's load points. Pads, statics, and ground units do not block it. Outside that 500 m the build is refused and the pilot is told they are not within 500 m of a FARP or Logistics Center. The hospital is a `Tent04` named `<name> tent`. `ctld.ensureKitTemplate` copies `RH_TPL_BLUE_MASH_KIT` when that group is missing, so **FARP AND MASH** lists MASH Crate. Building it calls `logistics.buildMash`.

CSAR uses `RH_TPL_DOWNED_PILOT` and the MOOSE CSAR module. Drop-off is that tent, on the ground, within 150 m. Capacity stays unlimited until transport tasks matter.

### The rest

Outposts, factories, red air, paratroopers, lives, map markers, convoys, and the live map each have their own module and start from `RH.start`. Red ground units in this build spawn from templates again. They are not saved and restored as live groups. That persistence was removed with the MASH rollback.

## Do not repeat

- Do not rebuild a FARP with `coalition.addGroup`. The dynamic-spawn list uses `coalition.addStaticObject` with `dynamicSpawn = true`, or the pad already saved in the mission.
- Do not zero a warehouse to make it limited.
- Do not respawn units from `persistence/Rotorheads.json` inside a `.miz`.
